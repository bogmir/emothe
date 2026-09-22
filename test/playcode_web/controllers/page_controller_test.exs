defmodule PlaycodeWeb.PageControllerTest do
  use PlaycodeWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "EMOTHE"
  end
end
