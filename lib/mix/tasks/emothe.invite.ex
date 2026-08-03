defmodule Mix.Tasks.Emothe.Invite do
  @shortdoc "Invites a user, optionally printing the link instead of mailing it"

  @moduledoc """
  Invites a user to EMOTHE.

      mix emothe.invite ana@uv.es
      mix emothe.invite ana@uv.es --admin
      mix emothe.invite ana@uv.es --admin --print-url

  `--print-url` writes the accept-invite link to stdout instead of sending
  mail. Use it on a fresh deployment where SMTP is not configured yet — the
  invitation that would let you configure the app cannot otherwise arrive.
  """

  use Mix.Task

  alias Emothe.Accounts
  alias Emothe.Accounts.AdminBootstrap

  @impl Mix.Task
  def run(args) do
    {opts, argv, _} =
      OptionParser.parse(args, strict: [admin: :boolean, print_url: :boolean])

    email =
      case argv do
        [email] -> email
        _ -> Mix.raise("usage: mix emothe.invite EMAIL [--admin] [--print-url]")
      end

    Mix.Task.run("app.start")

    role = if opts[:admin], do: :admin, else: :researcher

    case Accounts.invite_user(email, role, nil) do
      {:ok, user, token} ->
        if opts[:print_url] do
          Mix.shell().info(AdminBootstrap.invite_url(token))
        else
          case Accounts.deliver_invite(user, token, &AdminBootstrap.invite_url/1) do
            {:ok, _email} ->
              Mix.shell().info("invitation sent to #{email}")

            {:error, reason} ->
              Mix.raise("""
              #{email} was invited but the mail was not delivered: #{inspect(reason)}

              The account exists. Re-run with --print-url to get the link:

                  mix emothe.invite #{email}#{if opts[:admin], do: " --admin"} --print-url
              """)
          end
        end

      {:error, :already_active} ->
        Mix.raise("#{email} already has an active account")

      {:error, reason} ->
        Mix.raise("could not invite #{email}: #{inspect(reason)}")
    end
  end
end
