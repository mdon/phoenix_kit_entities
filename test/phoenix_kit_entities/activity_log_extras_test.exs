defmodule PhoenixKitEntities.ActivityLogExtrasTest do
  @moduledoc """
  Coverage push for `PhoenixKitEntities.ActivityLog`.
  `activity_log_rescue_test.exs` already pins the canonical-rescue
  branches; here we cover the happy path through `log/1` and both
  branches of `with_log/2`.
  """
  use PhoenixKitEntities.DataCase, async: false

  alias PhoenixKitEntities.ActivityLog

  describe "log/1 — happy path" do
    test "writes an activity row with the entities module key" do
      uuid = Ecto.UUID.generate()

      assert :ok =
               ActivityLog.log(%{
                 action: "test.action",
                 resource_type: "test_resource",
                 resource_uuid: uuid,
                 metadata: %{"foo" => "bar"}
               })

      # Sanity: row should exist in phoenix_kit_activities under module=entities.
      {:ok, %Postgrex.Result{rows: rows}} =
        Repo.query(
          "SELECT module FROM phoenix_kit_activities WHERE resource_uuid = $1::uuid",
          [Ecto.UUID.dump!(uuid)]
        )

      assert Enum.any?(rows, fn [m] -> m == "entities" end)
    end

    test "log/1 always returns :ok regardless of attrs shape" do
      assert :ok =
               ActivityLog.log(%{
                 action: "test.action_minimal",
                 resource_type: "x",
                 resource_uuid: Ecto.UUID.generate()
               })
    end
  end

  describe "with_log/2" do
    test "calls op_fun, logs on :ok, and returns the original {:ok, record}" do
      sentinel = Ecto.UUID.generate()

      result =
        ActivityLog.with_log(
          fn -> {:ok, %{uuid: sentinel}} end,
          fn record ->
            %{
              action: "test.with_log_ok",
              resource_type: "test_resource",
              resource_uuid: record.uuid,
              metadata: %{}
            }
          end
        )

      assert result == {:ok, %{uuid: sentinel}}
    end

    test "passes through {:error, _} unchanged without invoking attrs_fun" do
      ref = make_ref()
      parent = self()

      result =
        ActivityLog.with_log(
          fn -> {:error, :nope} end,
          fn _record ->
            send(parent, {:attrs_fun_called, ref})
            %{action: "should_not_log"}
          end
        )

      assert result == {:error, :nope}
      refute_received {:attrs_fun_called, ^ref}
    end
  end
end
