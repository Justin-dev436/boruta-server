defmodule BorutaAdminWeb.UserSocket do
  use Phoenix.Socket

  alias Boruta.Oauth.Authorization
  alias BorutaAdminWeb.Authorization

  ## Channels
  channel "metrics:*", BorutaAdminWeb.MetricsChannel

  @dialyzer {:no_match, connect: 3}
  def connect(%{"token" => token}, socket, _connect_info) do
    case Authorization.introspect(token) do
      {:ok, %{"active" => true, "sub" => sub}} ->
        {:ok, assign(socket, :user_id, sub)}
      {:ok, %{"active" => false}} -> :error
      {:error, _reason} -> :error
    end
  end
  def connect(_params, _socket, _connect_info) do
    :error
  end

  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end