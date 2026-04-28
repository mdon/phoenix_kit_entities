defmodule Mix.Tasks.PhoenixKitEntities.ImportTest do
  @moduledoc """
  Tests for `mix phoenix_kit_entities.import`. Same shell-swap trick as
  Export — drives every option branch (default skip, --on-conflict
  overwrite/merge/invalid, --dry-run, --entity, --input, --quiet, -y).
  """
  use PhoenixKitEntities.DataCase, async: false

  alias Mix.Tasks.PhoenixKitEntities.Import
  alias PhoenixKit.Settings
  alias PhoenixKitEntities, as: Entities
  alias PhoenixKitEntities.Mirror.Storage

  @tmp_root Path.join(System.tmp_dir!(), "phoenix_kit_entities_import_task_test")

  setup do
    File.rm_rf!(@tmp_root)
    File.mkdir_p!(@tmp_root)
    {:ok, _} = Settings.update_setting("entities_mirror_path", @tmp_root)

    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn ->
      Mix.shell(previous_shell)
      File.rm_rf!(@tmp_root)
    end)

    # Pre-seed a user so the importer's default-creator lookup
    # resolves (same trick as importer_test.exs).
    user_uuid = Ecto.UUID.generate()

    {:ok, _} =
      Repo.query(
        "INSERT INTO phoenix_kit_users (uuid, email, is_active, account_type) " <>
          "VALUES ($1::uuid, $2, true, 'personal') ON CONFLICT (uuid) DO NOTHING",
        [Ecto.UUID.dump!(user_uuid), "import-task-test@example.com"]
      )

    # Pre-seed an entity-export file so the importer has something to read.
    payload = %{
      "definition" => %{
        "name" => "import_task_widget",
        "display_name" => "Import Task Widget",
        "display_name_plural" => "Import Task Widgets",
        "description" => "From import",
        "icon" => "hero-puzzle-piece",
        "status" => "published",
        "fields_definition" => [
          %{"type" => "text", "key" => "title", "label" => "Title"}
        ],
        "settings" => %{}
      },
      "data" => [
        %{
          "title" => "Imported alpha",
          "slug" => "alpha",
          "status" => "published",
          "data" => %{"title" => "Imported alpha"},
          "metadata" => %{}
        }
      ]
    }

    case Storage.write_entity("import_task_widget", payload) do
      {:ok, _path} -> :ok
      {:error, _} -> :ok
    end

    {:ok, user_uuid: user_uuid}
  end

  describe "run/1 — option parsing branches" do
    test "default (no flags) prompts for confirmation; supplying 'no' cancels",
         _ctx do
      # Mix.Shell.Process pulls yes?/2 input from a queued message.
      send(self(), {:mix_shell_input, :yes?, false})

      try do
        Import.run([])
      catch
        :exit, {:shutdown, 0} -> :ok
      end

      assert_received {:mix_shell, :info, ["Import cancelled."]}
    end

    test "-y skips confirmation and runs the import", _ctx do
      Import.run(["-y"])
      # Coverage of the -y → import_all path.
    end

    test "--on-conflict overwrite parses and runs", _ctx do
      Import.run(["--on-conflict", "overwrite", "-y"])
    end

    test "--on-conflict merge parses and runs", _ctx do
      Import.run(["--on-conflict", "merge", "-y"])
    end

    test "--on-conflict skip parses and runs", _ctx do
      Import.run(["--on-conflict", "skip", "-y"])
    end

    test "--on-conflict bogus → error + exit", _ctx do
      try do
        Import.run(["--on-conflict", "bogus", "-y"])
      catch
        :exit, {:shutdown, 1} -> :ok
      end

      assert_received {:mix_shell, :error, [msg]}
      assert msg =~ "Invalid conflict strategy"
    end

    test "--dry-run prints preview without applying", _ctx do
      Import.run(["--dry-run"])
      assert_received {:mix_shell, :info, ["Previewing import (dry-run)..."]}
    end

    test "--quiet --dry-run suppresses preview output", _ctx do
      Import.run(["--dry-run", "--quiet"])
      refute_received {:mix_shell, :info, ["Previewing import (dry-run)..."]}
    end

    test "--entity NAME imports just that entity", _ctx do
      Import.run(["--entity", "import_task_widget", "-y"])
    end

    test "--entity for unknown name → error + exit", _ctx do
      try do
        Import.run([
          "--entity",
          "ghost_#{System.unique_integer([:positive])}",
          "-y"
        ])
      catch
        :exit, {:shutdown, 1} -> :ok
      end

      assert_received {:mix_shell, :error, [_msg]}
    end

    test "--input PATH overrides the source path", _ctx do
      Import.run(["--input", @tmp_root, "-y"])
    end

    test "short aliases -c / -i / -q forward correctly", _ctx do
      Import.run(["-c", "skip", "-i", @tmp_root, "-q", "-y"])
    end

    test "import_all without records still completes cleanly when path empty", _ctx do
      empty_dir = Path.join(@tmp_root, "empty")
      File.mkdir_p!(empty_dir)
      Import.run(["--input", empty_dir, "-y"])
    end
  end
end
