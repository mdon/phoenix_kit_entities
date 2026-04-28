defmodule PhoenixKitEntities.UrlResolverMultilangTest do
  @moduledoc """
  Coverage push for `PhoenixKitEntities.UrlResolver`'s multilang
  branches. With the Languages module enabled and ≥2 languages
  configured, `single_language_mode?/0` returns false and the previously
  unreachable code paths in `add_public_locale_prefix/2`,
  `build_path_with_language/3`, and `primary_language_base?/1` execute.

  Setup pattern: write `languages_enabled` + `languages_config` settings
  directly via the public API. Sandbox rolls back at test exit so the
  global Languages state is fresh for every test.
  """
  use PhoenixKitEntities.DataCase, async: false

  alias PhoenixKit.Settings
  alias PhoenixKitEntities.UrlResolver

  setup do
    config = %{
      "languages" => [
        %{
          "code" => "en",
          "name" => "English",
          "is_default" => true,
          "is_enabled" => true,
          "position" => 1
        },
        %{
          "code" => "es",
          "name" => "Spanish",
          "is_default" => false,
          "is_enabled" => true,
          "position" => 2
        },
        %{
          "code" => "fr",
          "name" => "French",
          "is_default" => false,
          "is_enabled" => true,
          "position" => 3
        }
      ]
    }

    Settings.update_setting("languages_enabled", "true")
    # languages_config is read via get_json_setting_cached → value_json
    # column. update_json_setting/2 writes to that column; the plain
    # update_setting writes to value (varchar 255) which truncates.
    Settings.update_json_setting("languages_config", config)

    on_exit(fn ->
      Settings.update_setting("languages_enabled", "false")
    end)

    :ok
  end

  describe "single_language_mode?/0" do
    test "returns false when ≥2 enabled languages are configured" do
      refute UrlResolver.single_language_mode?()
    end
  end

  describe "build_path_with_language/3 in multilang mode" do
    test "prepends the base locale code as a path prefix" do
      result = UrlResolver.build_path_with_language("/products/widget", "es")
      assert result == "/es/products/widget"
    end

    test "extracts the base from a dialect form (es-ES → es)" do
      result = UrlResolver.build_path_with_language("/products/widget", "es-ES")
      assert result == "/es/products/widget"
    end

    test "passes path through unchanged when language is nil" do
      assert UrlResolver.build_path_with_language("/foo", nil) == "/foo"
    end
  end

  describe "add_public_locale_prefix/2 in multilang mode" do
    test "primary language gets no prefix" do
      assert UrlResolver.add_public_locale_prefix("/foo", "en") == "/foo"
    end

    test "primary dialect (en-US) also gets no prefix because base matches" do
      assert UrlResolver.add_public_locale_prefix("/foo", "en-US") == "/foo"
    end

    test "non-primary base prepends /es" do
      assert UrlResolver.add_public_locale_prefix("/foo", "es") == "/es/foo"
    end

    test "non-primary dialect (es-ES) prepends /es (base extraction)" do
      assert UrlResolver.add_public_locale_prefix("/foo", "es-ES") == "/es/foo"
    end

    test "another non-primary language (fr) prepends /fr" do
      assert UrlResolver.add_public_locale_prefix("/foo", "fr") == "/fr/foo"
    end

    test "malformed locale falls through to unchanged path (safe_base_code rejects)" do
      # safe_base_code/1 rejects anything that doesn't match ^[a-z]{2,3}$
      assert UrlResolver.add_public_locale_prefix("/foo", "../etc/passwd") == "/foo"
      assert UrlResolver.add_public_locale_prefix("/foo", "12") == "/foo"
      assert UrlResolver.add_public_locale_prefix("/foo", "EN") == "/foo"
    end

    test "nil and empty stay unchanged" do
      assert UrlResolver.add_public_locale_prefix("/foo", nil) == "/foo"
      assert UrlResolver.add_public_locale_prefix("/foo", "") == "/foo"
    end
  end
end
