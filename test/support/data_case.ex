defmodule PhoenixKitEntities.DataCase do
  @moduledoc """
  Test case for tests requiring database access.

  Uses PhoenixKitEntities.Test.Repo with SQL Sandbox for isolation.
  Tests using this case are tagged `:integration` and will be
  automatically excluded when the database is unavailable.

  ## Usage

      defmodule MyModule.Integration.SomeTest do
        use PhoenixKitEntities.DataCase, async: true

        test "creates a record" do
          # Repo is available, transactions are isolated
        end
      end
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @moduletag :integration

      alias PhoenixKitEntities.Test.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import PhoenixKitEntities.ActivityLogAssertions
      import PhoenixKitEntities.DataCase
    end
  end

  alias Ecto.Adapters.SQL.Sandbox
  alias PhoenixKitEntities.Test.Repo, as: TestRepo

  setup tags do
    pid = Sandbox.start_owner!(TestRepo, shared: not tags[:async])

    on_exit(fn -> Sandbox.stop_owner(pid) end)

    :ok
  end

  @doc """
  Translates changeset errors into a flat map of `field => [messages]`,
  matching the helper Phoenix scaffolds in app DataCases. Used by
  changeset tests to assert on validation errors without coupling to
  the exact error tuple shape.

      iex> errors_on(changeset)[:name]
      ["can't be blank"]
  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  # Computed at compile time so the `bcrypt_elixir` cost is paid once
  # per suite, not once per test. The salt+hash baked into the module
  # is stable for the life of the compiled test_support beam.
  @valid_test_password_hash Bcrypt.hash_pwd_salt("test")

  @doc """
  Returns a valid bcrypt hash for seeding `phoenix_kit_users.hashed_password`
  in test fixtures.

  Replaces the hand-typed `"$2b$12$placeholder"` strings, which are
  syntactically valid bcrypt prefixes but malformed payloads —
  `Bcrypt.verify_pass/2` against them crashes rather than returning
  `false`. Tests that seed and never authenticate still gain by
  removing the foot-gun for any future caller that does.

  The verifiable plaintext is `"test"` for any test that needs it.
  """
  @spec valid_test_password_hash() :: String.t()
  def valid_test_password_hash, do: @valid_test_password_hash
end
