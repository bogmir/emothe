defmodule Emothe.Release do
  @moduledoc false

  @app :emothe

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Prints an accept-invite URL for `email`, creating the invitation if needed.

  Break-glass for a deployment whose SMTP is not working yet.
  """
  def invite_url(email, role \\ :admin) do
    load_app()
    {:ok, _} = Application.ensure_all_started(:emothe)

    case Emothe.Accounts.invite_user(email, role, nil) do
      {:ok, _user, token} ->
        IO.puts(Emothe.Accounts.AdminBootstrap.invite_url(token))

      {:error, reason} ->
        IO.puts("could not invite #{email}: #{inspect(reason)}")
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
