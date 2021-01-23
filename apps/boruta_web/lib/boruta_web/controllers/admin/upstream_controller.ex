defmodule BorutaWeb.Admin.UpstreamController do
  use BorutaWeb, :controller

  alias BorutaGateway.Upstreams
  alias BorutaGateway.Upstreams.Upstream

  plug BorutaWeb.AuthorizationPlug, ["upstreams:manage:all"]

  action_fallback BorutaWeb.FallbackController

  def index(conn, _params) do
    upstreams = Upstreams.list_upstreams()
    render(conn, "index.json", upstreams: upstreams)
  end

  def create(conn, %{"upstream" => upstream_params}) do
    with {:ok, %Upstream{} = upstream} <- Upstreams.create_upstream(upstream_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", Routes.admin_upstream_path(conn, :show, upstream))
      |> render("show.json", upstream: upstream)
    end
  end

  def show(conn, %{"id" => id}) do
    upstream = Upstreams.get_upstream!(id)
    render(conn, "show.json", upstream: upstream)
  end

  def update(conn, %{"id" => id, "upstream" => upstream_params}) do
    upstream = Upstreams.get_upstream!(id)

    with {:ok, %Upstream{} = upstream} <- Upstreams.update_upstream(upstream, upstream_params) do
      render(conn, "show.json", upstream: upstream)
    end
  end

  def delete(conn, %{"id" => id}) do
    upstream = Upstreams.get_upstream!(id)

    with {:ok, %Upstream{}} <- Upstreams.delete_upstream(upstream) do
      send_resp(conn, :no_content, "")
    end
  end
end