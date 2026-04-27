defmodule PhoenixKitEntities.ActivityLogRescueTest do
  @moduledoc """
  Pins the canonical rescue shape on `PhoenixKitEntities.ActivityLog.log/1`.

  The publishing-module sweep surfaced that an ActivityLog wrapper that
  catches a generic `error ->` and emits `Logger.warning(...)` produces
  noise during async tests when sandbox-crossing raises
  `DBConnection.OwnershipError`, and that `Postgrex.Error` arises in
  hosts that haven't yet run V97 (the activity table). The canonical
  shape from AGENTS.md:1947-1966 silently swallows both as `:ok`, falls
  back to `Logger.warning` for other rescues, and adds a
  `catch :exit, _ -> :ok` for sandbox-shutdown paths.

  This test lives in its own `async: false` file because it
  `DROP TABLE`s `phoenix_kit_activities` mid-transaction (sandbox rolls
  it back at test exit; see AGENTS.md:374-385 "Drop tables inside the
  sandboxed transaction").
  """
  use PhoenixKitEntities.DataCase, async: false

  import ExUnit.CaptureLog

  alias PhoenixKitEntities.ActivityLog

  describe "log/1 — canonical rescue shape" do
    test "swallows Postgrex.Error silently when activities table is missing" do
      Repo.query!("DROP TABLE IF EXISTS phoenix_kit_activities CASCADE")

      log =
        capture_log(fn ->
          assert :ok =
                   ActivityLog.log(%{
                     action: "entity.created",
                     resource_type: "entity",
                     resource_uuid: Ecto.UUID.generate(),
                     metadata: %{"name" => "rescue_test"}
                   })
        end)

      # The Postgrex.Error rescue swallows silently — no Logger.warning.
      refute log =~ "PhoenixKitEntities activity log failed"
    end

    test "log/1 returns :ok for any well-shaped attrs map (smoke)" do
      # Happy-path smoke — confirms the function head exists with the
      # documented signature and doesn't raise on a routine call.
      assert :ok =
               ActivityLog.log(%{
                 action: "entity.smoke",
                 resource_type: "entity",
                 resource_uuid: Ecto.UUID.generate()
               })
    end
  end
end
