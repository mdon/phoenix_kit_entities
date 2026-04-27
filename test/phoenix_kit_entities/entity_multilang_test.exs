defmodule PhoenixKitEntities.EntityMultilangTest do
  use ExUnit.Case, async: true
  alias PhoenixKitEntities, as: Entities

  describe "resolve_language/2" do
    test "resolves entity metadata from settings.translations" do
      entity = %Entities{
        display_name: "Product",
        display_name_plural: "Products",
        description: "Standard product",
        settings: %{
          "translations" => %{
            "es-ES" => %{
              "display_name" => "Producto",
              "display_name_plural" => "Productos",
              "description" => "Producto estándar"
            }
          }
        }
      }

      resolved = Entities.resolve_language(entity, "es-ES")

      assert resolved.display_name == "Producto"
      assert resolved.display_name_plural == "Productos"
      assert resolved.description == "Producto estándar"
    end

    test "falls back to default fields when translation is missing" do
      entity = %Entities{
        display_name: "Product",
        settings: %{"translations" => %{}}
      }

      resolved = Entities.resolve_language(entity, "es-ES")
      assert resolved.display_name == "Product"
    end

    test "falls back to default fields when lang is nil" do
      entity = %Entities{display_name: "Product"}
      resolved = Entities.resolve_language(entity, nil)
      assert resolved.display_name == "Product"
    end
  end

  describe "maybe_resolve_lang/2" do
    test "resolves when lang option is present" do
      entity = %Entities{
        display_name: "Product",
        settings: %{"translations" => %{"es-ES" => %{"display_name" => "Producto"}}}
      }

      resolved = Entities.maybe_resolve_lang(entity, lang: "es-ES")
      assert resolved.display_name == "Producto"
    end

    test "skips resolution when lang is missing" do
      entity = %Entities{display_name: "Product"}
      resolved = Entities.maybe_resolve_lang(entity, [])
      assert resolved.display_name == "Product"
    end

    test "skips resolution when lang is nil in opts" do
      entity = %Entities{display_name: "Product"}
      resolved = Entities.maybe_resolve_lang(entity, lang: nil)
      assert resolved.display_name == "Product"
    end
  end

  describe "resolve_language/2 — defensive handling" do
    test "no settings (nil)" do
      entity = %Entities{display_name: "Product", settings: nil}
      assert Entities.resolve_language(entity, "es-ES").display_name == "Product"
    end

    test "empty settings" do
      entity = %Entities{display_name: "Product", settings: %{}}
      assert Entities.resolve_language(entity, "es-ES").display_name == "Product"
    end

    test "translations map present but target locale missing" do
      entity = %Entities{
        display_name: "Product",
        settings: %{"translations" => %{"fr-FR" => %{"display_name" => "Produit"}}}
      }

      assert Entities.resolve_language(entity, "es-ES").display_name == "Product"
    end

    test "per-field missing — mixed resolution" do
      entity = %Entities{
        display_name: "Product",
        display_name_plural: "Products",
        description: "English description",
        settings: %{
          "translations" => %{
            "es-ES" => %{"display_name" => "Producto"}
            # plural + description intentionally missing
          }
        }
      }

      resolved = Entities.resolve_language(entity, "es-ES")
      assert resolved.display_name == "Producto"
      # Missing translations fall back to primary values
      assert resolved.display_name_plural == "Products"
      assert resolved.description == "English description"
    end

    test "empty-string override falls back to primary" do
      entity = %Entities{
        display_name: "Product",
        settings: %{"translations" => %{"es-ES" => %{"display_name" => ""}}}
      }

      assert Entities.resolve_language(entity, "es-ES").display_name == "Product"
    end
  end

  describe "resolve_language/2 — dialect/base normalization" do
    # Translations are stored under whatever key `set_entity_translation/3`
    # saw — typically the dialect form. Callers may query with either dialect
    # (`Gettext.get_locale/1` returns `"en-US"` etc.) or base (URL params
    # expose `"en"`). Without normalization the dialect/base mismatch silently
    # misses and the UI falls back to primary-language labels.

    test "querying with base code matches stored dialect (es → es-ES)" do
      entity = %Entities{
        display_name: "Product",
        settings: %{"translations" => %{"es-ES" => %{"display_name" => "Producto"}}}
      }

      assert Entities.resolve_language(entity, "es").display_name == "Producto"
    end

    test "querying with dialect matches stored base (es-ES → es)" do
      entity = %Entities{
        display_name: "Product",
        settings: %{"translations" => %{"es" => %{"display_name" => "Producto"}}}
      }

      assert Entities.resolve_language(entity, "es-ES").display_name == "Producto"
    end

    test "exact match wins over base/dialect collapse" do
      entity = %Entities{
        display_name: "Product",
        settings: %{
          "translations" => %{
            "es" => %{"display_name" => "Producto base"},
            "es-ES" => %{"display_name" => "Producto España"}
          }
        }
      }

      # Asking for "es-ES" returns the exact-match value, not the base.
      assert Entities.resolve_language(entity, "es-ES").display_name == "Producto España"
    end

    test "multiple dialects of the same base — deterministic via sort" do
      entity = %Entities{
        display_name: "Product",
        settings: %{
          "translations" => %{
            "es-MX" => %{"display_name" => "Producto MX"},
            "es-AR" => %{"display_name" => "Producto AR"}
          }
        }
      }

      # Querying base "es" picks the lowest-sorted dialect deterministically
      # (es-AR sorts before es-MX), so the same input always yields the same
      # output.
      assert Entities.resolve_language(entity, "es").display_name == "Producto AR"
    end
  end

  describe "resolve_language/2 — edge cases on free-text fields" do
    test "Unicode characters round-trip intact (display_name)" do
      entity = %Entities{
        display_name: "Product",
        settings: %{
          "translations" => %{
            "ja" => %{"display_name" => "製品 — 日本語 ✓"}
          }
        }
      }

      assert Entities.resolve_language(entity, "ja").display_name == "製品 — 日本語 ✓"
    end

    test "SQL-metacharacter literals in translated value (no SQL execution path)" do
      payload = "Robert'); DROP TABLE entities;--"

      entity = %Entities{
        display_name: "Product",
        settings: %{"translations" => %{"es" => %{"display_name" => payload}}}
      }

      # `resolve_language/2` is a pure transform — no SQL — so the literal
      # round-trips. The point of this test is that the metacharacters don't
      # interact with anything under the hood.
      assert Entities.resolve_language(entity, "es").display_name == payload
    end

    test "very long translated string preserved (not silently truncated)" do
      long = String.duplicate("a", 4096)

      entity = %Entities{
        display_name: "Product",
        settings: %{"translations" => %{"es" => %{"description" => long}}}
      }

      assert Entities.resolve_language(entity, "es").description == long
    end

    test "translation value containing emoji round-trips intact" do
      entity = %Entities{
        display_name: "Product",
        settings: %{"translations" => %{"es" => %{"display_name" => "Producto 🎯 ✅"}}}
      }

      assert Entities.resolve_language(entity, "es").display_name == "Producto 🎯 ✅"
    end
  end

  describe "resolve_languages/2" do
    test "empty list" do
      assert Entities.resolve_languages([], "es-ES") == []
    end

    test "nil locale is a no-op" do
      entity = %Entities{display_name: "Product"}
      assert Entities.resolve_languages([entity], nil) == [entity]
    end

    test "resolves every element" do
      entities = [
        %Entities{
          display_name: "Product",
          settings: %{"translations" => %{"es-ES" => %{"display_name" => "Producto"}}}
        },
        %Entities{
          display_name: "Article",
          settings: %{"translations" => %{"es-ES" => %{"display_name" => "Artículo"}}}
        }
      ]

      resolved = Entities.resolve_languages(entities, "es-ES")
      assert Enum.map(resolved, & &1.display_name) == ["Producto", "Artículo"]
    end
  end
end
