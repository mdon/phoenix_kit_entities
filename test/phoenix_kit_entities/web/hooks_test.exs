defmodule PhoenixKitEntities.Web.HooksTest do
  use ExUnit.Case, async: true

  alias PhoenixKitEntities.Web.Hooks

  describe "format_ip/1" do
    test "formats IPv4 4-tuples" do
      assert Hooks.format_ip({172, 18, 0, 4}) == "172.18.0.4"
      assert Hooks.format_ip({127, 0, 0, 1}) == "127.0.0.1"
    end

    test "formats IPv6 8-tuples — the regression that issue #17 reported" do
      assert Hooks.format_ip({0, 0, 0, 0, 0, 65_535, 44_050, 4}) == "::ffff:172.18.0.4"
      assert Hooks.format_ip({0, 0, 0, 0, 0, 0, 0, 1}) == "::1"
    end

    test "returns \"unknown\" for non-IP-tuple input rather than raising" do
      assert Hooks.format_ip({}) == "unknown"
      assert Hooks.format_ip({1, 2, 3}) == "unknown"
      assert Hooks.format_ip(:bogus) == "unknown"
    end
  end
end
