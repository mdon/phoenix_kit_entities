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

  describe "add_public_locale_prefix/2 in multilang mode (default_language_no_prefix OFF)" do
    # OFF is the default state in this setup — `languages_enabled` is set
    # but no one writes `default_language_no_prefix`, so the getter falls
    # back to false. Primary languages get the prefix like every other.

    test "primary language gets the prefix (setting OFF)" do
      assert UrlResolver.add_public_locale_prefix("/foo", "en") == "/en/foo"
    end

    test "primary dialect (en-US) gets the prefix" do
      assert UrlResolver.add_public_locale_prefix("/foo", "en-US") == "/en/foo"
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
      # Uppercase "EN" extracts to "en" via DialectMapper. With the
      # setting OFF, primary languages get the prefix like everyone else;
      # this used to fall through to "no prefix" because the primary-
      # language branch short-circuited. Now both branches converge:
      # primary with setting off → prefix.
      assert UrlResolver.add_public_locale_prefix("/foo", "EN") == "/en/foo"
    end

    test "nil and empty stay unchanged" do
      assert UrlResolver.add_public_locale_prefix("/foo", nil) == "/foo"
      assert UrlResolver.add_public_locale_prefix("/foo", "") == "/foo"
    end
  end

  describe "add_public_locale_prefix/2 in multilang mode (default_language_no_prefix ON)" do
    setup do
      Settings.update_boolean_setting("default_language_no_prefix", true)
      on_exit(fn -> Settings.update_boolean_setting("default_language_no_prefix", false) end)
      :ok
    end

    test "primary language is stripped when setting is ON" do
      assert UrlResolver.add_public_locale_prefix("/foo", "en") == "/foo"
    end

    test "primary dialect is stripped when setting is ON (base matches)" do
      assert UrlResolver.add_public_locale_prefix("/foo", "en-US") == "/foo"
    end

    test "non-primary still gets the prefix when setting is ON" do
      assert UrlResolver.add_public_locale_prefix("/foo", "es") == "/es/foo"
      assert UrlResolver.add_public_locale_prefix("/foo", "fr") == "/fr/foo"
    end
  end

  describe "build_path_with_language/3 — sitemap honors the setting" do
    test "non-primary always emits prefix regardless of setting" do
      assert UrlResolver.build_path_with_language("/p/widget", "es", false) ==
               "/es/p/widget"
    end

    test "primary with setting OFF (default) emits the prefix" do
      assert UrlResolver.build_path_with_language("/p/widget", "en", true) ==
               "/en/p/widget"
    end

    test "primary with setting ON skips the prefix" do
      Settings.update_boolean_setting("default_language_no_prefix", true)
      on_exit(fn -> Settings.update_boolean_setting("default_language_no_prefix", false) end)

      assert UrlResolver.build_path_with_language("/p/widget", "en", true) ==
               "/p/widget"
    end
  end
end
