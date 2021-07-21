defmodule BorutaWeb.OpenidController do
  use BorutaWeb, :controller

  alias BorutaWeb.OauthView

  def jwks(conn, %{"client_id" => client_id}) do
    with %Boruta.Ecto.Client{} = client <- Boruta.Ecto.Admin.get_client!(client_id) do
      conn
      |> put_view(OauthView)
      |> render("jwks.json", client: client)
    end
  end
end
