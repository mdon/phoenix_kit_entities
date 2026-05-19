defmodule PhoenixKitEntities.EntityDataUrlMultilangTest do
  @moduledoc """
  Integration coverage for `EntityData.public_path/3` and
  `public_alternates/3` crossing the `UrlResolver.add_public_locale_prefix/2`
  helper.

  The helper is unit-tested in isolation in `url_resolver_multilang_test.exs`,
  but the path *through* `EntityData.public_path/3` is what host apps
  actually call. This file pins the end-to-end shape under both states
  of the site-wide `default_language_no_prefix` setting so the helper
  + caller contract stays observed if either side refactors.
  """

  use PhoenixKitEntities.DataCase, async: false

  alias PhoenixKit.Modules.Languages
  alias PhoenixKit.Settings
  alias PhoenixKitEntities.EntityData

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
        }
      ]
    }

    Settings.update_setting("languages_enabled", "true")
    Settings.update_json_setting("languages_config", config)

    on_exit(fn ->
      Settings.update_setting("languages_enabled", "false")
      Languages.set_default_language_no_prefix(false)
    end)

    entity = %{name: "product", settings: %{"sitemap_url_pattern" => "/products/:slug"}}
    record = %{uuid: "uuid-1", slug: "my-item"}
    cache = %{entity_patterns: %{}, entity_index_paths: %{}}

    {:ok, entity: entity, record: record, cache: cache}
  end

  describe "public_path/3 — multilang, setting OFF (default)" do
    test "primary locale gets the prefix (canonical prefixed shape)", ctx do
      assert EntityData.public_path(ctx.entity, ctx.record,
               routes_cache: ctx.cache,
               locale: "en"
             ) == "/en/products/my-item"
    end

    test "non-primary locale gets its own prefix", ctx do
      assert EntityData.public_path(ctx.entity, ctx.record,
               routes_cache: ctx.cache,
               locale: "es"
             ) == "/es/products/my-item"
    end

    test "nil locale returns bare path", ctx do
      assert EntityData.public_path(ctx.entity, ctx.record, routes_cache: ctx.cache) ==
               "/products/my-item"
    end
  end

  describe "public_path/3 — multilang, setting ON" do
    setup do
      Languages.set_default_language_no_prefix(true)
      :ok
    end

    test "primary locale is stripped (canonical prefixless shape)", ctx do
      assert EntityData.public_path(ctx.entity, ctx.record,
               routes_cache: ctx.cache,
               locale: "en"
             ) == "/products/my-item"
    end

    test "non-primary locale still gets its prefix", ctx do
      assert EntityData.public_path(ctx.entity, ctx.record,
               routes_cache: ctx.cache,
               locale: "es"
             ) == "/es/products/my-item"
    end
  end

  describe "public_alternates/3 — multilang canonical + hreflang URLs" do
    test "with setting OFF, canonical is prefixed for primary", ctx do
      result =
        EntityData.public_alternates(ctx.entity, ctx.record,
          routes_cache: ctx.cache,
          base_url: "https://shop.example.com"
        )

      # Primary language canonical includes /en/
      assert result.canonical == "https://shop.example.com/en/products/my-item"

      # Alternates include both languages + x-default
      hrefs = Enum.map(result.alternates, & &1.href)
      assert "https://shop.example.com/en/products/my-item" in hrefs
      assert "https://shop.example.com/es/products/my-item" in hrefs

      # x-default points to the canonical primary URL
      assert Enum.find(result.alternates, &(&1.locale == "x-default")).href ==
               "https://shop.example.com/en/products/my-item"
    end

    test "with setting ON, canonical is prefixless for primary", ctx do
      Languages.set_default_language_no_prefix(true)

      result =
        EntityData.public_alternates(ctx.entity, ctx.record,
          routes_cache: ctx.cache,
          base_url: "https://shop.example.com"
        )

      assert result.canonical == "https://shop.example.com/products/my-item"

      hrefs = Enum.map(result.alternates, & &1.href)
      assert "https://shop.example.com/products/my-item" in hrefs
      assert "https://shop.example.com/es/products/my-item" in hrefs

      assert Enum.find(result.alternates, &(&1.locale == "x-default")).href ==
               "https://shop.example.com/products/my-item"
    end
  end
end
