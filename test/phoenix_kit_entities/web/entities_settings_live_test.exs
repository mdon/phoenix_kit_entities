defmodule PhoenixKitEntities.Web.EntitiesSettingsLiveTest do
  use PhoenixKitEntities.LiveCase, async: false

  alias PhoenixKitEntities, as: Entities

  setup do
    actor_uuid = Ecto.UUID.generate()
    {:ok, actor_uuid: actor_uuid}
  end

  describe "mount" do
    test "renders settings page with system status panel", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, _view, html} = live(conn, "/en/admin/settings/entities")

      assert html =~ "Entities Settings"
      assert html =~ "System Status"
    end
  end

  describe "enable_entities / disable_entities" do
    test "disable_entities toggles the setting + logs module.entities.disabled",
         %{conn: conn} = ctx do
      # Start enabled so the disable button renders
      {:ok, _} = Entities.enable_system(actor_uuid: ctx.actor_uuid)

      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, "/en/admin/settings/entities")

      view
      |> element("button[phx-click='disable_entities']")
      |> render_click()

      assert_activity_logged("module.entities.disabled",
        actor_uuid: ctx.actor_uuid,
        metadata_has: %{"setting" => "entities_enabled"}
      )

      assert render(view) =~ "disabled successfully"
    end

    test "enable_entities toggles the setting + logs module.entities.enabled",
         %{conn: conn} = ctx do
      {:ok, _} = Entities.disable_system(actor_uuid: ctx.actor_uuid)

      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, "/en/admin/settings/entities")

      view
      |> element("button[phx-click='enable_entities']")
      |> render_click()

      assert_activity_logged("module.entities.enabled",
        actor_uuid: ctx.actor_uuid,
        metadata_has: %{"setting" => "entities_enabled"}
      )

      assert render(view) =~ "enabled successfully"
    end

    test "disable_entities button has phx-disable-with set", %{conn: conn} = ctx do
      {:ok, _} = Entities.enable_system(actor_uuid: ctx.actor_uuid)
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, _view, html} = live(conn, "/en/admin/settings/entities")

      # delta-pin: phx-disable-with on every async/destructive button (C5)
      assert html =~ ~r/phx-click="disable_entities"[^>]*phx-disable-with=/
    end
  end

  describe "handle_info catch-all" do
    test "ignores unrelated messages without crashing",
         %{conn: conn} = ctx do
      {:ok, _} = Entities.enable_system(actor_uuid: ctx.actor_uuid)
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, "/en/admin/settings/entities")

      send(view.pid, {:unrelated_message, :payload})
      assert render(view) =~ "Entities System"
    end

    test "logs at :debug level so unexpected messages stay visible in dev",
         %{conn: conn} = ctx do
      {:ok, _} = Entities.enable_system(actor_uuid: ctx.actor_uuid)
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, "/en/admin/settings/entities")

      previous = Logger.level()
      Logger.configure(level: :debug)
      on_exit(fn -> Logger.configure(level: previous) end)

      log =
        ExUnit.CaptureLog.capture_log([level: :debug], fn ->
          send(view.pid, {:unhandled_in_test, :payload})
          render(view)
        end)

      assert log =~ "EntitiesSettings: unhandled handle_info"
    end
  end
end
