defmodule PhoenixKitEntities.Test.Repo.Migrations.AddRoleTables do
  use Ecto.Migration

  @moduledoc """
  Adds the `phoenix_kit_user_roles` + `phoenix_kit_user_role_assignments`
  tables that `PhoenixKit.Users.Auth.get_first_admin/0` /
  `get_first_user/0` query. Without these tables the
  `Mirror.Importer.create_entity_from_import/1` path crashes mid-
  transaction and poisons the sandbox. New migration (rather than
  edits to the original) so an existing test DB doesn't need to be
  dropped to pick up the schema change.
  """

  def up do
    create_if_not_exists table(:phoenix_kit_user_roles, primary_key: false) do
      add(:uuid, :uuid, primary_key: true, default: fragment("uuid_generate_v7()"))
      add(:name, :string, null: false)
      add(:description, :string)
      add(:is_system_role, :boolean, default: false)
      add(:is_active, :boolean, default: true)
      add(:inserted_at, :utc_datetime, null: false, default: fragment("NOW()"))
      add(:updated_at, :utc_datetime, null: false, default: fragment("NOW()"))
    end

    create_if_not_exists(unique_index(:phoenix_kit_user_roles, [:name]))

    create_if_not_exists table(:phoenix_kit_user_role_assignments, primary_key: false) do
      add(:uuid, :uuid, primary_key: true, default: fragment("uuid_generate_v7()"))
      add(:user_uuid, :uuid, null: false)
      add(:role_uuid, :uuid, null: false)
      add(:assigned_by_uuid, :uuid)
      add(:assigned_at, :utc_datetime)
      add(:is_active, :boolean, default: true)
      add(:inserted_at, :utc_datetime, null: false, default: fragment("NOW()"))
    end

    create_if_not_exists(index(:phoenix_kit_user_role_assignments, [:user_uuid]))
    create_if_not_exists(index(:phoenix_kit_user_role_assignments, [:role_uuid]))
  end

  def down do
    drop_if_exists(table(:phoenix_kit_user_role_assignments))
    drop_if_exists(table(:phoenix_kit_user_roles))
  end
end
