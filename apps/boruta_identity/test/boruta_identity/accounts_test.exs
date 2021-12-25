defmodule BorutaIdentity.AccountsTest do
  use BorutaIdentity.DataCase

  import BorutaIdentity.AccountsFixtures
  import BorutaIdentity.Factory

  alias BorutaIdentity.Accounts
  alias BorutaIdentity.Accounts.RegistrationError
  alias BorutaIdentity.Accounts.{User, UserAuthorizedScope, UserToken}
  alias BorutaIdentity.RelyingParties.ClientRelyingParty
  alias BorutaIdentity.Repo

  defmodule DummyRegistration do
    @behaviour Accounts.RegistrationApplication

    def user_initialized(context, changeset) do
      {:user_initialized, context, changeset}
    end

    def registration_failure(context, error) do
      {:registration_failure, context, error}
    end
  end

  describe "Utils.client_implementation/1" do
    test "returns an error when client_id is nil" do
      client_id = nil

      assert Accounts.Utils.client_implementation(client_id) ==
               {:error, "Cannot register without specifying a client."}
    end

    test "returns an error when client_id is unknown" do
      client_id = SecureRandom.uuid()

      assert Accounts.Utils.client_implementation(client_id) ==
               {:error,
                "Relying Party not configured for given OAuth client. " <>
                  "Please contact your administrator."}
    end

    test "returns client relying party implementation" do
      relying_party = BorutaIdentity.Factory.insert(:relying_party, type: "internal")

      %ClientRelyingParty{client_id: client_id} =
        BorutaIdentity.Factory.insert(:client_relying_party, relying_party: relying_party)

      assert Accounts.Utils.client_implementation(client_id) ==
               {:ok, BorutaIdentity.Accounts.Internal}
    end
  end

  describe "list_users/0" do
    test "returns an empty list" do
      assert Accounts.list_users() == []
    end

    test "returns users" do
      user = user_fixture()
      assert Accounts.list_users() == [user]
    end
  end

  describe "get_user/1" do
    test "returns nil" do
      assert Accounts.get_user(Ecto.UUID.generate()) == nil
    end

    test "returns an user" do
      user = user_fixture()
      assert Accounts.get_user(user.id) == user
    end
  end

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "check_user_password/2" do
    test "returns an error" do
      user = user_fixture()
      assert Accounts.check_user_password(user, "bad password") == {:error, "Invalid password."}
    end

    test "returns :ok" do
      user = user_fixture()
      assert Accounts.check_user_password(user, valid_user_password()) == :ok
    end
  end

  describe "register/3" do
    setup do
      client_relying_party = BorutaIdentity.Factory.insert(:client_relying_party)

      {:ok, client_id: client_relying_party.client_id}
    end

    test "requires email and password to be set", %{client_id: client_id} do
      {:error, changeset} = Accounts.register(client_id, %{}, & &1)

      assert %{
               password: ["can't be blank"],
               email: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates email and password when given", %{client_id: client_id} do
      {:error, changeset} =
        Accounts.register(client_id, %{email: "not valid", password: "not valid"}, & &1)

      assert %{
               email: ["must have the @ sign and no spaces"],
               password: ["should be at least 12 character(s)"]
             } = errors_on(changeset)
    end

    test "validates maximum values for email and password for security", %{client_id: client_id} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.register(client_id, %{email: too_long, password: too_long}, & &1)

      assert "should be at most 160 character(s)" in errors_on(changeset).email
      assert "should be at most 80 character(s)" in errors_on(changeset).password
    end

    test "validates email uniqueness", %{client_id: client_id} do
      %{email: email} = user_fixture()
      {:error, changeset} = Accounts.register(client_id, %{email: email}, & &1)
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the upper cased email too, to check that email case is ignored.
      {:error, changeset} = Accounts.register(client_id, %{email: String.upcase(email)}, & &1)
      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers users with a hashed password", %{client_id: client_id} do
      email = unique_user_email()

      {:ok, user} =
        Accounts.register(client_id, %{email: email, password: valid_user_password()}, & &1)

      assert user.email == email
      assert is_binary(user.hashed_password)
      assert is_nil(user.confirmed_at)
      assert is_nil(user.password)
    end

    @tag :skip
    test "delivers a confirmation mail"
  end

  describe "initialize_registration/3" do
    setup do
      client_relying_party = BorutaIdentity.Factory.insert(:client_relying_party)

      {:ok, client_id: client_relying_party.client_id}
    end

    test "returns an error with nil client_id" do
      client_id = nil
      context = :context

      assert {:registration_failure, ^context, %RegistrationError{} = error} =
               Accounts.initialize_registration(context, client_id, DummyRegistration)
      assert error.message == "Cannot register without specifying a client."
    end

    test "returns an error with unknown client_id" do
      client_id = SecureRandom.uuid()
      context = :context

      assert {:registration_failure, ^context, %RegistrationError{} = error} =
               Accounts.initialize_registration(context, client_id, DummyRegistration)
      assert error.message == "Relying Party not configured for given OAuth client. Please contact your administrator."
    end

    test "returns a changeset", %{client_id: client_id} do
      context = :context

      assert {:user_initialized, ^context, %Ecto.Changeset{} = changeset} =
               Accounts.initialize_registration(context, client_id, DummyRegistration)

      assert changeset.required == [:password, :email]
    end
  end

  describe "apply_user_email/3" do
    setup do
      %{user: user_fixture()}
    end

    test "requires email to change", %{user: user} do
      {:error, changeset} = Accounts.apply_user_email(user, valid_user_password(), %{})
      assert %{email: ["did not change"]} = errors_on(changeset)
    end

    test "validates email", %{user: user} do
      {:error, changeset} =
        Accounts.apply_user_email(user, valid_user_password(), %{email: "not valid"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates maximum value for email for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.apply_user_email(user, valid_user_password(), %{email: too_long})

      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness", %{user: user} do
      %{email: email} = user_fixture()

      {:error, changeset} =
        Accounts.apply_user_email(user, valid_user_password(), %{email: email})

      assert "has already been taken" in errors_on(changeset).email
    end

    test "validates current password", %{user: user} do
      {:error, changeset} =
        Accounts.apply_user_email(user, "invalid", %{email: unique_user_email()})

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end

    test "applies the email without persisting it", %{user: user} do
      email = unique_user_email()
      {:ok, user} = Accounts.apply_user_email(user, valid_user_password(), %{email: email})
      assert user.email == email
      assert Accounts.get_user(user.id).email != email
    end
  end

  describe "deliver_update_email_instructions/3" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_update_email_instructions(user, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@example.com"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{user: user, token: token, email: email} do
      assert Accounts.update_user_email(user, token) == :ok
      changed_user = Repo.get!(User, user.id)
      assert changed_user.email != user.email
      assert changed_user.email == email
      assert changed_user.confirmed_at
      assert changed_user.confirmed_at != user.confirmed_at
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email with invalid token", %{user: user} do
      assert Accounts.update_user_email(user, "oops") == :error
      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if user email changed", %{user: user, token: token} do
      assert Accounts.update_user_email(%{user | email: "current@example.com"}, token) == :error
      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      assert Accounts.update_user_email(user, token) == :error
      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "change_user_password/2" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_password(%User{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_user_password(%User{}, %{
          "password" => "new valid password"
        })

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_user_password/3" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.update_user_password(user, valid_user_password(), %{password: too_long})

      assert "should be at most 80 character(s)" in errors_on(changeset).password
    end

    test "validates current password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, "invalid", %{password: valid_user_password()})

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end

    test "updates the password", %{user: user} do
      {:ok, user} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: "new valid password"
        })

      assert is_nil(user.password)
      assert user = Accounts.get_user_by_email(user.email)
      assert :ok = Accounts.check_user_password(user, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, _} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: "new valid password"
        })

      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "delete_user/1" do
    test "returns an error" do
      assert Accounts.delete_user(Ecto.UUID.generate()) == {:error, "User not found."}
    end

    test "returns deleted user" do
      %User{id: user_id} = user_fixture()
      assert {:ok, %User{id: ^user_id}} = Accounts.delete_user(user_id)
      assert Repo.get(User, user_id) == nil
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert session_user = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "delete_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "deliver_user_confirmation_instructions/2" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      confirmation_url_fun = fn _ -> "http://test.host" end
      {:ok, token} = Accounts.deliver_user_confirmation_instructions(user, confirmation_url_fun)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "confirm"
    end
  end

  describe "confirm_user/2" do
    setup do
      user = user_fixture()

      confirmation_url_fun = fn _ -> "http://test.host" end
      {:ok, token} = Accounts.deliver_user_confirmation_instructions(user, confirmation_url_fun)

      %{user: user, token: token}
    end

    test "confirms the email with a valid token", %{user: user, token: token} do
      assert {:ok, confirmed_user} = Accounts.confirm_user(token)
      assert confirmed_user.confirmed_at
      assert confirmed_user.confirmed_at != user.confirmed_at
      assert Repo.get!(User, user.id).confirmed_at
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not confirm with invalid token", %{user: user} do
      assert Accounts.confirm_user("oops") == :error
      refute Repo.get!(User, user.id).confirmed_at
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not confirm email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      assert Accounts.confirm_user(token) == :error
      refute Repo.get!(User, user.id).confirmed_at
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "deliver_user_reset_password_instructions/2" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      reset_password_url_fun = fn _ -> "http://test.host" end

      {:ok, token} =
        Accounts.deliver_user_reset_password_instructions(user, reset_password_url_fun)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "reset_password"
    end
  end

  describe "get_user_by_reset_password_token/1" do
    setup do
      user = user_fixture()

      reset_password_url_fun = fn _ -> "http://test.host" end

      {:ok, token} =
        Accounts.deliver_user_reset_password_instructions(user, reset_password_url_fun)

      %{user: user, token: token}
    end

    test "returns the user with valid token", %{user: %{id: id}, token: token} do
      assert %User{id: ^id} = Accounts.get_user_by_reset_password_token(token)
      assert Repo.get_by(UserToken, user_id: id)
    end

    test "does not return the user with invalid token", %{user: user} do
      refute Accounts.get_user_by_reset_password_token("oops")
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not return the user if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_reset_password_token(token)
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "reset_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.reset_user_password(user, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.reset_user_password(user, %{password: too_long})
      assert "should be at most 80 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{user: user} do
      {:ok, updated_user} = Accounts.reset_user_password(user, %{password: "new valid password"})
      assert is_nil(updated_user.password)
      assert user = Accounts.get_user_by_email(user.email)
      assert :ok = Accounts.check_user_password(user, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)
      {:ok, _} = Accounts.reset_user_password(user, %{password: "new valid password"})
      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "inspect/2" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end

  describe "update_user_authorized_scopes/2" do
    test "returns an error on duplicates" do
      user = user_fixture()

      {:error, %Ecto.Changeset{} = changeset} =
        Accounts.update_user_authorized_scopes(user, [%{"name" => "test"}, %{"name" => "test"}])

      assert changeset
    end

    test "stores user scopes" do
      user = user_fixture()

      {:ok,
       %User{
         authorized_scopes:
           [
             %UserAuthorizedScope{
               name: "test"
             }
           ] = authorized_scopes
       }} = Accounts.update_user_authorized_scopes(user, [%{"name" => "test"}])

      assert Repo.all(UserAuthorizedScope) == authorized_scopes
    end
  end

  describe "get_user_scopes/1" do
    test "returns an empty list" do
      user = user_fixture()

      assert Accounts.get_user_scopes(user.id) == []
    end

    test "returns authorized scopes" do
      user = user_fixture()
      scope = user_scopes_fixture(user)

      assert Accounts.get_user_scopes(user.id) == [scope]
    end
  end

  describe "consent/2" do
    setup do
      user = user_fixture()

      {:ok, user: user}
    end

    test "returns an error with invalid params", %{user: user} do
      scopes = []
      client_id = nil

      assert {:error, %Ecto.Changeset{}} =
               Accounts.consent(user, %{"client_id" => client_id, "scopes" => scopes})
    end

    test "adds user consent for a given client_id", %{user: user} do
      scopes = ["scope:a", "scope:b"]
      client_id = "client_id"

      {:ok, %User{consents: [consent]}} =
        Accounts.consent(user, %{"client_id" => client_id, "scopes" => scopes})

      assert consent.client_id == client_id
      assert consent.scopes == scopes

      %User{consents: [consent]} = Repo.one(User) |> Repo.preload(:consents)

      assert consent.client_id == client_id
      assert consent.scopes == scopes
    end
  end

  describe "consented?/2" do
    setup do
      user = user_fixture()
      client_id = SecureRandom.uuid()
      redirect_uri = "http://test.host"
      consent = insert(:consent, user: user, scopes: ["consented", "scope"])

      oauth_request = %Plug.Conn{
        query_params: %{
          "scope" => "",
          "response_type" => "token",
          "client_id" => client_id,
          "redirect_uri" => redirect_uri
        }
      }

      oauth_request_with_scope = %Plug.Conn{
        query_params: %{
          "scope" => "scope:a scope:b",
          "response_type" => "token",
          "client_id" => client_id,
          "redirect_uri" => redirect_uri
        }
      }

      oauth_request_with_consented_scope = %Plug.Conn{
        query_params: %{
          "scope" => "consented scope",
          "response_type" => "token",
          "client_id" => consent.client_id,
          "redirect_uri" => redirect_uri
        }
      }

      {:ok,
       user: user,
       oauth_request: oauth_request,
       oauth_request_with_scope: oauth_request_with_scope,
       oauth_request_with_consented_scope: oauth_request_with_consented_scope}
    end

    test "returns false with not an oauth request", %{user: user} do
      assert Accounts.consented?(user, %Plug.Conn{}) == false
    end

    test "returns true with empty scope", %{user: user, oauth_request: oauth_request} do
      assert Accounts.consented?(user, oauth_request) == true
    end

    test "returns false when scopes are not consented", %{
      user: user,
      oauth_request_with_scope: oauth_request
    } do
      assert Accounts.consented?(user, oauth_request) == false
    end

    test "returns true when scopes are consented", %{
      user: user,
      oauth_request_with_consented_scope: oauth_request
    } do
      assert Accounts.consented?(user, oauth_request) == true
    end
  end

  describe "consented_scopes/2" do
    setup do
      user = user_fixture()
      client_id = SecureRandom.uuid()
      consent = insert(:consent, user: user, scopes: ["consented:scope"])

      redirect_uri = "http://test.host"

      oauth_request = %Plug.Conn{
        query_params: %{
          "scope" => "",
          "response_type" => "token",
          "client_id" => client_id,
          "redirect_uri" => redirect_uri
        }
      }

      oauth_request_with_consented_scopes = %Plug.Conn{
        query_params: %{
          "scope" => "scope:a scope:b",
          "response_type" => "token",
          "client_id" => consent.client_id,
          "redirect_uri" => redirect_uri
        }
      }

      {:ok,
       user: user,
       consent: consent,
       oauth_request: oauth_request,
       oauth_request_with_consented_scopes: oauth_request_with_consented_scopes}
    end

    test "returns an empty array", %{user: user} do
      assert Accounts.consented_scopes(user, %Plug.Conn{}) == []
    end

    test "returns an empty array with a valid oauth request", %{
      user: user,
      oauth_request: oauth_request
    } do
      assert Accounts.consented_scopes(user, oauth_request) == []
    end

    test "returns existing consented scopes", %{
      user: user,
      oauth_request_with_consented_scopes: oauth_request
    } do
      assert Accounts.consented_scopes(user, oauth_request) == ["consented:scope"]
    end
  end
end
