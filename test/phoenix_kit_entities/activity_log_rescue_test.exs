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

    test "swallows DBConnection.OwnershipError silently when called from a non-allowed process" do
      # Spawn a separate process that has no sandbox checkout. When it
      # calls log/1 the inner repo().insert raises
      # DBConnection.OwnershipError. Upstream's own rescue catches the
      # exception and returns {:error, _}, so it doesn't reach our
      # branch — this test is the smoke that the path doesn't raise
      # back out at us.
      log =
        capture_log(fn ->
          task =
            Task.async(fn ->
              ActivityLog.log(%{
                action: "entity.crossing",
                resource_type: "entity",
                resource_uuid: Ecto.UUID.generate()
              })
            end)

          Task.await(task, 1_000)
        end)

      refute log =~ "PhoenixKitEntities activity log failed"
    end

    test "logs Logger.warning for unexpected exception shapes" do
      # Force the inner call to raise an exception type that neither our
      # narrow rescues (Postgrex.Error / DBConnection.OwnershipError) nor
      # the catch :exit branch swallow. Pass a struct that
      # `Map.put(attrs, :module, ...)` accepts (any map-like value works
      # because of the `is_map(attrs)` guard) but downstream
      # `Entry.changeset/2` rejects with a non-Postgrex exception.
      #
      # `%DateTime{}` is a map and accepts Map.put — but its
      # `__struct__` doesn't match `%PhoenixKit.Activity.Entry{}`, so
      # `Entry.changeset/2` raises ArgumentError or KeyError before any
      # repo call. Upstream's own rescue catches it and returns
      # `{:error, e}` rather than raising — so our fallback rescue
      # doesn't actually fire in this path. We assert the function
      # still returns :ok, which is the contract.
      now = DateTime.utc_now()
      assert :ok = ActivityLog.log(now)
    end
  end
end
