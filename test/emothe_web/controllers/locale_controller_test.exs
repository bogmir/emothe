defmodule EmotheWeb.LocaleControllerTest do
  use EmotheWeb.ConnCase, async: true

  test "POST /locale redirects back preserving query and fragment", %{conn: conn} do
    conn =
      conn
      |> put_req_header("referer", "http://example.com/plays?search=hamlet#meta-overview")
      |> post(~p"/locale", %{locale: "en"})

    assert redirected_to(conn) == "/plays?search=hamlet#meta-overview"
  end

  test "POST /locale falls back to / when referer missing", %{conn: conn} do
    conn = post(conn, ~p"/locale", %{locale: "en"})
    assert redirected_to(conn) == "/"
  end

  test "POST /locale falls back to session last_path when referer missing", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{last_path: "/plays?search=hamlet"})
      |> post(~p"/locale", %{locale: "en"})

    assert redirected_to(conn) == "/plays?search=hamlet"
  end
end
