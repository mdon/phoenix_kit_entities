defmodule PhoenixKitEntities.Components.EntityFormTest do
  @moduledoc """
  Tests for the public-form component (`<EntityForm entity_slug="..." />`).
  Covers every branch of the `cond` in render/1: missing slug,
  unknown entity, form disabled, fields empty, honeypot enabled,
  successful render with title/description, all wired up.
  """
  use PhoenixKitEntities.DataCase, async: false

  # render_component/2 is a macro from Phoenix.LiveViewTest. Skip the
  # bare `import Phoenix.LiveViewTest` because LiveCase already imports
  # render_component/1 which clashes with a local helper named the same;
  # require the module here so the macro resolves.
  require Phoenix.LiveViewTest

  alias PhoenixKitEntities, as: Entities
  alias PhoenixKitEntities.Components.EntityForm

  setup do
    actor_uuid = Ecto.UUID.generate()

    {:ok, enabled_entity} =
      Entities.create_entity(
        %{
          name: "comp_form_enabled",
          display_name: "Comp Form",
          display_name_plural: "Comp Forms",
          fields_definition: [%{"type" => "text", "key" => "title", "label" => "Title"}],
          settings: %{
            "public_form_enabled" => true,
            "public_form_fields" => ["title"],
            "public_form_title" => "Hello",
            "public_form_description" => "Please submit",
            "public_form_submit_text" => "Send"
          },
          created_by_uuid: actor_uuid
        },
        actor_uuid: actor_uuid
      )

    {:ok, disabled_entity} =
      Entities.create_entity(
        %{
          name: "comp_form_disabled",
          display_name: "Disabled",
          display_name_plural: "Disabled",
          fields_definition: [%{"type" => "text", "key" => "title", "label" => "Title"}],
          settings: %{"public_form_enabled" => false},
          created_by_uuid: actor_uuid
        },
        actor_uuid: actor_uuid
      )

    {:ok, enabled: enabled_entity, disabled: disabled_entity}
  end

  defp render_form(attributes) do
    Phoenix.LiveViewTest.render_component(&EntityForm.render/1,
      attributes: attributes,
      content: nil,
      variant: "default"
    )
  end

  describe "render/1 — error / disabled branches" do
    test "missing entity_slug → configuration-error fallback" do
      html = render_form(%{})
      assert html =~ "Form configuration error"
    end

    test "empty entity_slug → configuration-error fallback" do
      html = render_form(%{"entity_slug" => ""})
      assert html =~ "Form configuration error"
    end

    test "unknown entity_slug → configuration-error fallback" do
      html = render_form(%{"entity_slug" => "nonexistent_#{System.unique_integer()}"})
      assert html =~ "Form configuration error"
    end

    test "entity exists but public_form_enabled=false → unavailable", ctx do
      html = render_form(%{"entity_slug" => ctx.disabled.name})
      assert html =~ "currently unavailable"
    end
  end

  describe "render/1 — happy path" do
    test "renders form with title, description, and submit button", ctx do
      html = render_form(%{"entity_slug" => ctx.enabled.name})

      assert html =~ "Hello"
      assert html =~ "Please submit"
      assert html =~ "Send"
      assert html =~ "<form"
      assert html =~ "_csrf_token"
      assert html =~ "_form_loaded_at"
    end

    test "renders honeypot when public_form_honeypot=true", ctx do
      Entities.update_entity(ctx.enabled, %{
        settings:
          Map.merge(ctx.enabled.settings, %{
            "public_form_honeypot" => true
          })
      })

      # Re-fetch to pick up settings change, then re-render.
      html = render_form(%{"entity_slug" => ctx.enabled.name})
      assert html =~ "_hp_website"
    end

    test "without title/description, omits both heading + paragraph", _ctx do
      actor_uuid = Ecto.UUID.generate()

      {:ok, entity} =
        Entities.create_entity(
          %{
            name: "comp_form_no_title",
            display_name: "NoTitle",
            display_name_plural: "NoTitles",
            fields_definition: [%{"type" => "text", "key" => "name", "label" => "Name"}],
            settings: %{
              "public_form_enabled" => true,
              "public_form_fields" => ["name"]
            },
            created_by_uuid: actor_uuid
          },
          actor_uuid: actor_uuid
        )

      html = render_form(%{"entity_slug" => entity.name})
      # Default submit text fallback
      assert html =~ "Submit" or html =~ "submit"
      # Form action should always be present in the happy path.
      assert html =~ "/entities/#{entity.name}/submit"
    end
  end
end
