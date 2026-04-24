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
  end
end
