defmodule Emothe.Accounts.UserNotifier do
  import Swoosh.Email

  require Logger

  alias Emothe.Mailer

  defp from_address do
    {"EMOTHE", Application.get_env(:emothe, :mail_from, "noreply@emothe.uv.es")}
  end

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(from_address())
      |> subject(subject)
      |> text_body(body)

    # Logged here rather than at the call sites: the forgot-password flow must
    # answer the same way whether or not the address exists, so a failure there
    # has nowhere else to surface. A dropped invitation or reset link is a
    # lockout, and a lockout must never be silent.
    case Mailer.deliver(email) do
      {:ok, _metadata} ->
        {:ok, email}

      {:error, reason} = error ->
        Logger.error("could not send #{inspect(subject)} to #{recipient}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Deliver an invitation to join EMOTHE.
  """
  def deliver_invite_instructions(user, url) do
    deliver(user.email, "You have been invited to EMOTHE", """

    ==============================

    Hi #{user.email},

    You have been invited to the EMOTHE platform. Set your password by
    visiting the URL below:

    #{url}

    This invitation expires in 7 days. If you were not expecting it, ignore
    this message.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Reset password instructions", """

    ==============================

    Hi #{user.email},

    You can reset your password by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end
end
