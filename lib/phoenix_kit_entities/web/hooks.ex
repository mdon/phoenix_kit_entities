defmodule PhoenixKitEntities.Web.Hooks do
  @moduledoc """
  LiveView hooks for entity module pages.

  Provides common setup and subscriptions for all entity-related LiveViews.
  """

  import Phoenix.LiveView
  alias PhoenixKit.Admin.Presence
  alias PhoenixKit.Users.Auth.Scope
  alias PhoenixKit.Utils.Date, as: UtilsDate
  alias PhoenixKitEntities.Events

  @doc """
  Subscribes to entity events and tracks user presence when the LiveView is connected.

  Add this to your entity LiveView with:

      on_mount PhoenixKitEntities.Web.Hooks

  This automatically:
  - Subscribes to entity creation, update, and deletion events
  - Tracks authenticated user presence for dashboard statistics
  """
  def on_mount(:default, _params, session, socket) do
    if connected?(socket) do
      Events.subscribe_to_entities()
      track_page_visit(socket, session)
    end

    {:cont, socket}
  end

  defp track_page_visit(socket, session) do
    scope = socket.assigns[:phoenix_kit_current_scope]

    if scope && Scope.authenticated?(scope) do
      user = %{
        uuid: Scope.user_uuid(scope),
        email: Scope.user_email(scope)
      }

      session_id = session["live_socket_id"] || generate_session_id()

      Presence.track_user(user, %{
        connected_at: UtilsDate.utc_now(),
        session_id: session_id,
        current_page: get_current_page(socket),
        ip_address: extract_ip(socket),
        user_agent: get_connect_info(socket, :user_agent)
      })
    end
  end

  defp get_current_page(socket) do
    # Try to get from socket assigns, fallback to generic entities page
    socket.assigns[:current_path] || "/admin/entities"
  end

  defp extract_ip(socket) do
    case get_connect_info(socket, :peer_data) do
      %{address: address} when is_tuple(address) -> format_ip(address)
      _ -> "unknown"
    end
  end

  @doc false
  # Exposed for unit tests — handles both IPv4 4-tuples and IPv6 8-tuples
  # (incl. the IPv4-mapped `::ffff:a.b.c.d` form Docker bridge networks emit).
  @spec format_ip(:inet.ip_address() | term()) :: String.t()
  def format_ip(address) do
    case :inet.ntoa(address) do
      {:error, _} -> "unknown"
      chars -> to_string(chars)
    end
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64()
  end
end
