defmodule BorutaIdentityWeb.UserRegistrationController do
  @behaviour BorutaIdentity.Accounts.RegistrationApplication

  use BorutaIdentityWeb, :controller

  import BorutaIdentityWeb.Authenticable, only: [log_in: 2]

  alias BorutaIdentity.Accounts
  alias BorutaIdentity.Accounts.RegistrationError

  def new(conn, _params) do
    client_id = get_session(conn, :current_client_id)

    Accounts.initialize_registration(conn, client_id, __MODULE__)
  end

  @impl BorutaIdentity.Accounts.RegistrationApplication
  def user_initialized(conn, changeset) do
    render(conn, "new.html", changeset: changeset)
  end

  @impl BorutaIdentity.Accounts.RegistrationApplication
  def registration_failure(conn, %RegistrationError{message: message}) do
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> put_flash(:error, message)
    |> redirect(to: user_return_to || "/")
  end

  def create(conn, %{"user" => user_params}) do
    client_id = get_session(conn, :current_client_id)

    case Accounts.register(
           client_id,
           user_params,
           &Routes.user_confirmation_url(conn, :confirm, &1)
         ) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "User created successfully.")
        |> log_in(user)

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html", changeset: changeset)

      {:error, reason} ->
        user_return_to = get_session(conn, :user_return_to)

        conn
        |> put_flash(:error, reason)
        |> redirect(to: user_return_to || "/")
    end
  end
end
