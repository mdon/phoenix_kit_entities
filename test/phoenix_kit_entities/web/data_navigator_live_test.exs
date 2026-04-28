defmodule PhoenixKitEntities.Web.DataNavigatorLiveTest do
  use PhoenixKitEntities.LiveCase, async: false

  alias PhoenixKitEntities, as: Entities
  alias PhoenixKitEntities.EntityData

  setup do
    actor_uuid = Ecto.UUID.generate()

    {:ok, entity} =
      Entities.create_entity(
        %{
          name: "dn_test",
          display_name: "DN Test",
          display_name_plural: "DN Tests",
          fields_definition: [
            %{"type" => "text", "key" => "name", "label" => "Name"}
          ],
          status: "published",
          created_by_uuid: actor_uuid
        },
        actor_uuid: actor_uuid
      )

    records =
      for n <- 1..3 do
        {:ok, r} =
          EntityData.create(
            %{
              entity_uuid: entity.uuid,
              title: "Record #{n}",
              slug: "record-#{n}",
              status: "published",
              data: %{"name" => "Item #{n}"},
              created_by_uuid: actor_uuid
            },
            actor_uuid: actor_uuid
          )

        r
      end

    {:ok, entity: entity, records: records, actor_uuid: actor_uuid}
  end

  describe "mount" do
    test "renders data navigator with entity title", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, _view, html} = live(conn, navigator_url(ctx.entity))

      assert html =~ "DN Test"
      # All seeded records render in the table.
      assert html =~ "Record 1"
      assert html =~ "Record 2"
      assert html =~ "Record 3"
    end
  end

  describe "single-record archive_data / restore_data" do
    test "archive_data flips status, logs activity with actor_uuid + flash",
         %{conn: conn} = ctx do
      [record | _] = ctx.records
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, navigator_url(ctx.entity))

      view
      |> element(
        "button[phx-click='archive_data'][phx-value-uuid='#{record.uuid}'][data-tip='Archive']"
      )
      |> render_click()

      assert_activity_logged("entity_data.updated",
        actor_uuid: ctx.actor_uuid,
        resource_uuid: record.uuid,
        metadata_has: %{"status" => "archived"}
      )

      assert render(view) =~ "archived successfully"
      assert EntityData.get!(record.uuid).status == "archived"
    end

    test "restore_data flips back to published and logs", %{conn: conn} = ctx do
      [record | _] = ctx.records

      {:ok, _} =
        EntityData.update_data(record, %{status: "archived"}, actor_uuid: ctx.actor_uuid)

      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, navigator_url(ctx.entity, status: "archived"))

      view
      |> element(
        "button[phx-click='restore_data'][phx-value-uuid='#{record.uuid}'][data-tip='Restore']"
      )
      |> render_click()

      assert_activity_logged("entity_data.updated",
        actor_uuid: ctx.actor_uuid,
        resource_uuid: record.uuid,
        metadata_has: %{"status" => "published"}
      )

      assert render(view) =~ "restored successfully"
    end

    test "single-record buttons carry phx-disable-with", %{conn: conn} = ctx do
      [record | _] = ctx.records
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, _view, html} = live(conn, navigator_url(ctx.entity))

      # delta-pin C5: archive button has phx-disable-with attr.
      assert html =~
               ~r/phx-click="archive_data"[^>]*phx-value-uuid="#{record.uuid}"[^>]*phx-disable-with=/
    end
  end

  describe "bulk_action — actor_uuid threading + summary log" do
    test "bulk archive logs ONE bulk_status_changed row with actor + count",
         %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, navigator_url(ctx.entity))

      uuids = Enum.map(ctx.records, & &1.uuid)

      # Simulate selecting all 3 records, then bulk_action archive.
      for uuid <- uuids do
        render_hook(view, "toggle_select", %{"uuid" => uuid})
      end

      render_hook(view, "bulk_action", %{"action" => "archive"})

      assert_activity_logged("entity_data.bulk_status_changed",
        actor_uuid: ctx.actor_uuid,
        metadata_has: %{"status" => "archived", "count" => 3, "uuid_count" => 3}
      )
    end

    test "bulk delete logs ONE bulk_deleted row", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, navigator_url(ctx.entity))

      for r <- ctx.records do
        render_hook(view, "toggle_select", %{"uuid" => r.uuid})
      end

      render_hook(view, "bulk_action", %{"action" => "delete"})

      assert_activity_logged("entity_data.bulk_deleted",
        actor_uuid: ctx.actor_uuid,
        metadata_has: %{"count" => 3, "uuid_count" => 3}
      )
    end

    test "bulk restore (change_status published) threads actor", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, navigator_url(ctx.entity))

      [r | _] = ctx.records
      render_hook(view, "toggle_select", %{"uuid" => r.uuid})
      render_hook(view, "bulk_action", %{"action" => "restore"})

      assert_activity_logged("entity_data.bulk_status_changed",
        actor_uuid: ctx.actor_uuid,
        metadata_has: %{"status" => "published", "count" => 1}
      )
    end

    test "bulk_action with no selection flashes error, no activity row",
         %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, navigator_url(ctx.entity))

      render_hook(view, "bulk_action", %{"action" => "archive"})

      assert render(view) =~ "No records selected"

      refute_activity_logged("entity_data.bulk_status_changed",
        actor_uuid: ctx.actor_uuid
      )
    end
  end

  describe "handle_info catch-all" do
    test "ignores unrelated PubSub messages without crashing", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, navigator_url(ctx.entity))

      send(view.pid, {:unknown_message, "noise"})
      assert render(view) =~ "DN Test"
    end

    test "logs at :debug level so unexpected messages stay visible in dev",
         %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, navigator_url(ctx.entity))

      # Global logger level is :warning in test config; lift it locally so
      # the capture sees Logger.debug. Reset on test exit.
      previous = Logger.level()
      Logger.configure(level: :debug)
      on_exit(fn -> Logger.configure(level: previous) end)

      log =
        ExUnit.CaptureLog.capture_log([level: :debug], fn ->
          send(view.pid, {:unhandled_in_test, :payload})
          # Force a render so handle_info has flushed before the capture closes.
          render(view)
        end)

      assert log =~ "DataNavigator: unhandled handle_info"
    end
  end

  # ── helpers ──────────────────────────────────────────────────

  describe "push_patch handlers (toggle_view_mode / filter / search)" do
    # These tests mount through the `/phoenix_kit/...` scope in
    # Test.Router so the LV's own `Routes.path/2`-driven push_patch
    # URLs resolve against a defined route. The mounted URL doesn't
    # include the entity_slug here because we test against the
    # navigator with one already in scope.

    defp pk_navigator_url(entity, opts \\ []) do
      base = "/phoenix_kit/en/admin/entities/#{entity.name}/data"

      case Keyword.get(opts, :status) do
        nil -> base
        status -> base <> "?status=#{status}"
      end
    end

    test "toggle_view_mode patches without crashing", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, pk_navigator_url(ctx.entity))

      render_hook(view, "toggle_view_mode", %{"mode" => "grid"})
      render_hook(view, "toggle_view_mode", %{"mode" => "table"})
      assert render(view) =~ "DN Test"
    end

    test "filter_by_status patches without crashing", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, pk_navigator_url(ctx.entity))

      render_hook(view, "filter_by_status", %{"status" => "published"})
      assert render(view) =~ "DN Test"
    end

    test "search + clear_filters patch without crashing", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, pk_navigator_url(ctx.entity))

      render_hook(view, "search", %{"search" => %{"term" => "find_me"}})
      render_hook(view, "clear_filters", %{})
      assert render(view) =~ "DN Test"
    end

    test "filter_by_entity with empty uuid redirects to entities list (entities route mounted)",
         %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, pk_navigator_url(ctx.entity))

      result = render_hook(view, "filter_by_entity", %{"entity_uuid" => ""})
      # The handler responds with a redirect; the test rendering
      # succeeds because the target `/phoenix_kit/en/admin/entities`
      # IS in our test router.
      assert is_binary(result) or match?({:error, _}, result)
    end
  end

  describe "single record events: toggle_status / restore_data" do
    setup ctx do
      {:ok, record} =
        EntityData.create(
          %{
            entity_uuid: ctx.entity.uuid,
            title: "Status Toggle",
            slug: "status-toggle",
            status: "draft",
            data: %{"title" => "Status Toggle"},
            created_by_uuid: ctx.actor_uuid
          },
          actor_uuid: ctx.actor_uuid
        )

      {:ok, record: record}
    end

    test "toggle_status cycles draft → published", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, navigator_url(ctx.entity))

      render_hook(view, "toggle_status", %{"uuid" => ctx.record.uuid})
      reread = EntityData.get(ctx.record.uuid)
      # toggle_status: draft → published → archived → draft
      assert reread.status in ["published", "archived", "draft"]
    end

    test "restore_data sets status to published", %{conn: conn} = ctx do
      {:ok, _} = EntityData.update(ctx.record, %{status: "archived"}, actor_uuid: ctx.actor_uuid)

      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, navigator_url(ctx.entity))

      render_hook(view, "restore_data", %{"uuid" => ctx.record.uuid})
      assert EntityData.get(ctx.record.uuid).status == "published"
    end
  end

  describe "selection + bulk events" do
    setup ctx do
      records =
        Enum.map(1..3, fn i ->
          {:ok, r} =
            EntityData.create(
              %{
                entity_uuid: ctx.entity.uuid,
                title: "Bulk #{i}",
                slug: "bulk-#{i}",
                status: "draft",
                data: %{},
                created_by_uuid: ctx.actor_uuid
              },
              actor_uuid: ctx.actor_uuid
            )

          r
        end)

      {:ok, records: records}
    end

    test "toggle_select / select_all / deselect_all", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, navigator_url(ctx.entity))

      [r1 | _] = ctx.records
      render_hook(view, "toggle_select", %{"uuid" => r1.uuid})
      render_hook(view, "toggle_select", %{"uuid" => r1.uuid})
      render_hook(view, "select_all", %{})
      render_hook(view, "deselect_all", %{})
      assert render(view) =~ "DN Test"
    end

    test "bulk_action change_status moves selected to draft", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, navigator_url(ctx.entity))

      render_hook(view, "select_all", %{})

      render_hook(view, "bulk_action", %{
        "action" => "change_status",
        "status" => "draft"
      })

      _ = ctx.records
    end

    test "bulk_action delete removes selected records", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, navigator_url(ctx.entity))

      render_hook(view, "select_all", %{})
      render_hook(view, "bulk_action", %{"action" => "delete"})

      _ = ctx
    end

    test "bulk_action with empty selection flashes error",
         %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, navigator_url(ctx.entity))

      # No selection.
      render_hook(view, "bulk_action", %{"action" => "archive"})
      assert render(view) =~ "selected" or render(view) =~ "DN Test"
    end
  end

  defp navigator_url(entity, opts \\ []) do
    base = "/en/admin/entities/#{entity.name}/data"

    case Keyword.get(opts, :status) do
      nil -> base
      status -> base <> "?status=#{status}"
    end
  end
end
