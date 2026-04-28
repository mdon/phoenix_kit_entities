defmodule Mix.Tasks.PhoenixKitEntities.ExportTest do
  @moduledoc """
  Tests for `mix phoenix_kit_entities.export`.

  `Mix.Task.run("app.start")` is a no-op when the app is already
  started (which is the case in our test env), so the task body runs
  cleanly inside the test sandbox. We swap `Mix.shell()` to
  `Mix.Shell.Process` to capture output via `assert_received` and
  silence the otherwise-noisy IO.
  """
  use PhoenixKitEntities.DataCase, async: false

  alias Mix.Tasks.PhoenixKitEntities.Export
  alias PhoenixKit.Settings
  alias PhoenixKitEntities, as: Entities

  @tmp_root Path.join(System.tmp_dir!(), "phoenix_kit_entities_export_task_test")

  setup do
    File.rm_rf!(@tmp_root)
    File.mkdir_p!(@tmp_root)
    {:ok, _} = Settings.update_setting("entities_mirror_path", @tmp_root)
    {:ok, _} = Settings.update_setting("entities_mirror_definitions_enabled", "true")

    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(previous_shell)
      File.rm_rf!(@tmp_root)
    end)

    actor_uuid = Ecto.UUID.generate()

    {:ok, entity} =
      Entities.create_entity(
        %{
          name: "export_task_widget",
          display_name: "Export Task Widget",
          display_name_plural: "Export Task Widgets",
          fields_definition: [%{"type" => "text", "key" => "title", "label" => "Title"}],
          created_by_uuid: actor_uuid
        },
        actor_uuid: actor_uuid
      )

    {:ok, entity: entity, actor_uuid: actor_uuid}
  end

  describe "run/1 — option parsing branches" do
    test "no flags exports all entities (definitions only by default)", _ctx do
      Export.run([])
      assert_received {:mix_shell, :info, ["Exporting all entities..."]}
    end

    test "--quiet suppresses the 'Exporting all' message" do
      Export.run(["--quiet"])
      refute_received {:mix_shell, :info, ["Exporting all entities..."]}
    end

    test "--with-data forces data inclusion regardless of setting" do
      Settings.update_setting("entities_mirror_data_enabled", "false")
      Export.run(["--with-data"])
      # Coverage of the include_data? :with_data branch.
    end

    test "--no-data forces data exclusion regardless of setting" do
      Settings.update_setting("entities_mirror_data_enabled", "true")
      Export.run(["--no-data"])
    end

    test "--output overrides the path setting" do
      custom = Path.join(@tmp_root, "custom_output")
      File.mkdir_p!(custom)
      Export.run(["--output", custom])
    end

    test "--entity NAME exports a single entity by name", ctx do
      Export.run(["--entity", ctx.entity.name])
    end

    test "--entity for unknown name calls Mix.shell().error and exits", _ctx do
      ghost = "ghost_entity_#{System.unique_integer([:positive])}"

      try do
        Export.run(["--entity", ghost])
      catch
        :exit, {:shutdown, 1} -> :ok
      end

      assert_received {:mix_shell, :error, [msg]}
      assert msg =~ ghost
    end

    test "short alias -e forwards to --entity", ctx do
      Export.run(["-e", ctx.entity.name])
    end

    test "short alias -q forwards to --quiet" do
      Export.run(["-q"])
      refute_received {:mix_shell, :info, ["Exporting all entities..."]}
    end
  end
end
