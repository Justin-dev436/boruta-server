defmodule BorutaIdentity.Accounts.Utils do
  @moduledoc false

  alias BorutaIdentity.RelyingParties
  alias BorutaIdentity.RelyingParties.RelyingParty

  defmacro __using__(_opts) do
    quote do
      import BorutaIdentity.Accounts.Utils,
        only: [
          client_implementation: 1,
          defdelegatetoclientimpl: 1
        ]
    end
  end

  @spec client_implementation(client_id :: String.t() | nil) ::
          {:ok, implementation :: atom()} | {:error, reason :: String.t()}
  def client_implementation(nil), do: {:error, "Cannot register without specifying a client."}

  def client_implementation(client_id) do
    case RelyingParties.get_relying_party_by_client_id(client_id) do
      %RelyingParty{} = relying_party ->
        {:ok, RelyingParty.implementation(relying_party)}

      nil ->
        {:error,
         "Relying Party not configured for given OAuth client. Please contact your administrator."}
    end
  end

  # TODO find a better way to delegate to the given client implementation
  defmacro defdelegatetoclientimpl(fun) do
    fun = Macro.escape(fun, unquote: true)

    quote bind_quoted: [fun: fun] do
      {name, params} = Macro.decompose_call(fun)
      client_id_param = Enum.find(params, fn {var, _, _} -> var == :client_id end)
      other_params = List.delete(params, client_id_param)

      def unquote({name, [line: __ENV__.line], params}) do
        with {:ok, implementation} <- client_implementation(unquote(client_id_param)) do
          apply(
            implementation,
            unquote(name),
            unquote(other_params)
          )
        end
      end
    end
  end
end

defmodule BorutaIdentity.Accounts do
  @moduledoc """
  The Accounts context.
  """

  alias BorutaIdentity.Accounts.Confirmations
  alias BorutaIdentity.Accounts.Consents
  alias BorutaIdentity.Accounts.Deliveries
  alias BorutaIdentity.Accounts.Registrations
  alias BorutaIdentity.Accounts.Sessions
  alias BorutaIdentity.Accounts.User
  alias BorutaIdentity.Accounts.Users

  use BorutaIdentity.Accounts.Utils

  ## WIP Registrations

  defmodule RegistrationError do
    @enforce_keys [:message]
    defexception [:user, :message, :changeset]

    @type t :: %__MODULE__{
      message: String.t(),
      user: BorutaIdentity.Accounts.User.t() | nil,
      changeset: Ecto.Changeset.t() | nil
    }

    def exception(message) when is_binary(message) do
      %__MODULE__{message: message}
    end

    def message(exception) do
      exception.message
    end
  end

  defmodule RegistrationApplication do
    @moduledoc """
    TODO RegistrationApplication documentation
    """

    @callback user_initialized(context :: any(), changeset :: Ecto.Changeset.t()) :: any()

    @callback registration_failure(context :: any(), error :: RegistrationError.t()) :: any()

    # TODO implement
    # @callback user_registered(context :: any(), user :: User.t()) :: any()
  end

  @spec initialize_registration(context :: any(), client_id :: String.t(), module :: atom()) ::
          callback_result :: any()
  def initialize_registration(context, client_id, module) do
    case client_implementation(client_id) do
      {:ok, implementation} ->
        changeset = apply(implementation, :registration_changeset, [%User{}])

        module.user_initialized(context, changeset)
      {:error, reason} ->
        module.registration_failure(context, %RegistrationError{message: reason})
    end
  end

  @callback registration_changeset(user :: User.t()) :: changeset :: Ecto.Changeset.t()

  defdelegatetoclientimpl(register(client_id, user_params, confirmation_url_fun))

  @callback register(
              user_params :: map(),
              confirmation_url_fun :: (token :: String.t() -> confirmation_url :: String.t())
            ) ::
              {:ok, user :: User.t()}
              | {:error, reason :: String.t()}
              | {:error, changeset :: Ecto.Changeset.t()}

  ## Database getters

  defdelegate list_users, to: Users
  defdelegate get_user(id), to: Users
  defdelegate get_user_by_email(email), to: Users
  defdelegate check_user_password(user, password), to: Users
  defdelegate get_user_by_session_token(token), to: Users
  defdelegate get_user_by_reset_password_token(token), to: Users
  defdelegate get_user_scopes(user_id), to: Users

  ## User settings

  defdelegate update_user_password(user, password, attrs), to: Registrations
  defdelegate change_user_password(user), to: Registrations
  defdelegate change_user_password(user, attrs), to: Registrations
  defdelegate reset_user_password(user, attrs), to: Registrations
  defdelegate update_user_authorized_scopes(user, scopes), to: Registrations
  defdelegate change_user_email(user), to: Registrations
  defdelegate change_user_email(user, attrs), to: Registrations
  defdelegate apply_user_email(user, password, attrs), to: Registrations
  defdelegate update_user_email(user, token), to: Registrations
  defdelegate delete_user(id), to: Registrations

  ## Delivery

  defdelegate deliver_update_email_instructions(user, current_email, update_email_url_fun),
    to: Deliveries

  defdelegate deliver_user_confirmation_instructions(user, confirmation_url_fun), to: Deliveries

  defdelegate deliver_user_reset_password_instructions(user, reset_password_url_fun),
    to: Deliveries

  ## Session

  defdelegate generate_user_session_token(user), to: Sessions
  defdelegate delete_session_token(token), to: Sessions

  ## Confirmation

  defdelegate confirm_user(token), to: Confirmations

  ## Consent
  defdelegate consent(user, attrs), to: Consents
  defdelegate consented?(user, conn), to: Consents
  defdelegate consented_scopes(user, conn), to: Consents
end
