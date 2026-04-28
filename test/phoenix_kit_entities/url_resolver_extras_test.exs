defmodule PhoenixKitEntities.UrlResolverExtrasTest do
  @moduledoc """
  Coverage push for `PhoenixKitEntities.UrlResolver` — fills gaps the
  original test file (`url_resolver_test.exs`) doesn't reach:
  add_public_locale_prefix branches, build_path_with_language,
  build_url, single_language_mode?, get_url_pattern_cached resolution
  chain, and get_index_path_cached resolution chain.
  """
  use PhoenixKitEntities.DataCase, async: false

  alias PhoenixKit.Settings
  alias PhoenixKitEntities.UrlResolver

  describe "build_path_with_language/3" do
    test "returns path unchanged in single-language mode" do
      # No languages configured → single_language_mode? returns true.
      assert UrlResolver.build_path_with_language("/foo", "es") == "/foo"
    end

    test "returns path unchanged when language is nil" do
      assert UrlResolver.build_path_with_language("/foo", nil) == "/foo"
    end
  end

  describe "add_public_locale_prefix/2" do
    test "nil locale → unchanged" do
      assert UrlResolver.add_public_locale_prefix("/foo", nil) == "/foo"
    end

    test "empty string locale → unchanged" do
      assert UrlResolver.add_public_locale_prefix("/foo", "") == "/foo"
    end

    test "single-language mode → unchanged regardless of locale" do
      assert UrlResolver.add_public_locale_prefix("/foo", "fr") == "/foo"
    end

    test "malformed locale (digits, special chars) → unchanged" do
      # Without Languages enabled, single_language_mode? returns true,
      # so any locale falls through to the unchanged path. Coverage
      # for the early-return clauses regardless.
      assert UrlResolver.add_public_locale_prefix("/foo", "1!@") == "/foo"
    end
  end

  describe "single_language_mode?/0" do
    test "returns true when Languages module is disabled" do
      assert UrlResolver.single_language_mode?()
    end
  end

  describe "build_url/2" do
    test "joins base with path" do
      assert UrlResolver.build_url("/foo", "https://example.com") == "https://example.com/foo"
    end

    test "trims trailing slash from base" do
      assert UrlResolver.build_url("/foo", "https://example.com/") == "https://example.com/foo"
    end

    test "falls back to site_url setting when base_url is nil" do
      Settings.update_setting("site_url", "https://from-settings.test")
      assert UrlResolver.build_url("/foo") == "https://from-settings.test/foo"
    end

    test "returns just the path when no base_url and no site_url setting" do
      # Empty string from missing setting + path = path
      Settings.update_setting("site_url", "")
      assert UrlResolver.build_url("/foo") == "/foo"
    end
  end

  describe "build_routes_cache/0" do
    test "returns a map with entity_patterns + entity_index_paths + content_routes" do
      cache = UrlResolver.build_routes_cache()
      assert is_map(cache)
      assert Map.has_key?(cache, :entity_patterns)
      assert Map.has_key?(cache, :entity_index_paths)
      assert Map.has_key?(cache, :content_routes)
    end
  end

  describe "get_url_pattern_cached/2" do
    test "uses entity.settings[\"sitemap_url_pattern\"] when present" do
      entity = %{
        name: "test_entity",
        settings: %{"sitemap_url_pattern" => "/custom/:slug"}
      }

      assert UrlResolver.get_url_pattern_cached(entity, %{
               entity_patterns: %{},
               entity_index_paths: %{},
               content_routes: []
             }) == "/custom/:slug"
    end

    test "falls back to per-entity sitemap_entity_<name>_pattern setting" do
      Settings.update_setting("sitemap_entity_widget_pattern", "/widgets/:slug")

      entity = %{name: "widget", settings: %{}}

      result =
        UrlResolver.get_url_pattern_cached(entity, %{
          entity_patterns: %{},
          entity_index_paths: %{},
          content_routes: []
        })

      assert result == "/widgets/:slug"
    end

    test "falls back to global sitemap_entities_pattern setting" do
      Settings.update_setting("sitemap_entities_pattern", "/all/:entity_name/:slug")

      entity = %{name: "gizmo", settings: %{}}

      result =
        UrlResolver.get_url_pattern_cached(entity, %{
          entity_patterns: %{},
          entity_index_paths: %{},
          content_routes: []
        })

      assert result == "/all/gizmo/:slug"
    end

    test "uses an explicit pattern from the routes cache" do
      entity = %{name: "thing", settings: %{}}

      result =
        UrlResolver.get_url_pattern_cached(entity, %{
          entity_patterns: %{"thing" => "/things/:slug"},
          entity_index_paths: %{},
          content_routes: []
        })

      assert result == "/things/:slug"
    end

    test "uses catchall route from cache, substituting entity name" do
      entity = %{name: "anything", settings: %{}}

      result =
        UrlResolver.get_url_pattern_cached(entity, %{
          entity_patterns: %{catchall: %{path: "/:entity_name/:slug"}},
          entity_index_paths: %{},
          content_routes: []
        })

      assert result == "/anything/:slug"
    end

    test "returns nil when nothing in any tier resolves" do
      entity = %{name: "ghost_#{System.unique_integer([:positive])}", settings: %{}}

      assert UrlResolver.get_url_pattern_cached(entity, %{
               entity_patterns: %{},
               entity_index_paths: %{},
               content_routes: []
             }) == nil
    end
  end

  describe "get_index_path_cached/2" do
    test "uses entity.settings[\"sitemap_index_path\"] when present" do
      entity = %{
        name: "thing",
        settings: %{"sitemap_index_path" => "/custom"}
      }

      assert UrlResolver.get_index_path_cached(entity, %{
               entity_patterns: %{},
               entity_index_paths: %{},
               content_routes: []
             }) == "/custom"
    end

    test "uses entity_index_paths from cache" do
      entity = %{name: "widget", settings: %{}}

      result =
        UrlResolver.get_index_path_cached(entity, %{
          entity_patterns: %{},
          entity_index_paths: %{"widget" => "/widgets"},
          content_routes: []
        })

      assert result == "/widgets"
    end

    test "uses catchall from index paths" do
      entity = %{name: "anything", settings: %{}}

      result =
        UrlResolver.get_index_path_cached(entity, %{
          entity_patterns: %{},
          entity_index_paths: %{catchall: %{path: "/:slug"}},
          content_routes: []
        })

      assert result == "/anything"
    end

    test "uses sitemap_entity_<name>_index_path setting" do
      Settings.update_setting("sitemap_entity_doodad_index_path", "/doodads")

      entity = %{name: "doodad", settings: %{}}

      result =
        UrlResolver.get_index_path_cached(entity, %{
          entity_patterns: %{},
          entity_index_paths: %{},
          content_routes: []
        })

      assert result == "/doodads"
    end

    test "auto-pattern fallback returns /<entity_name>" do
      Settings.update_setting("sitemap_entities_auto_pattern", "true")

      entity = %{name: "auto_thing_#{System.unique_integer([:positive])}", settings: %{}}

      result =
        UrlResolver.get_index_path_cached(entity, %{
          entity_patterns: %{},
          entity_index_paths: %{},
          content_routes: []
        })

      assert result == "/" <> entity.name
    end

    test "returns nil when no path can be resolved" do
      Settings.update_setting("sitemap_entities_auto_pattern", "false")

      entity = %{name: "ghost_#{System.unique_integer([:positive])}", settings: %{}}

      assert UrlResolver.get_index_path_cached(entity, %{
               entity_patterns: %{},
               entity_index_paths: %{},
               content_routes: []
             }) == nil
    end
  end
end
