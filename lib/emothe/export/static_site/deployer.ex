defmodule Emothe.Export.StaticSite.Deployer do
  @moduledoc """
  Deploys a generated static site to GitHub Pages by pushing to a `gh-pages` branch.
  """

  require Logger

  @doc """
  Deploy the static site directory to GitHub Pages.

  ## Options
    * `:branch` - target branch (default: `"gh-pages"`)
    * `:message` - commit message (default: auto-generated with timestamp)
    * `:on_progress` - `fun(String.t()) -> :ok` callback for status updates

  Returns `{:ok, url}` or `{:error, reason}`.
  """
  def deploy_to_github_pages(site_dir, repo, opts \\ []) do
    branch = opts[:branch] || "gh-pages"

    message =
      opts[:message] ||
        "Deploy EMOTHE static site — #{DateTime.utc_now() |> DateTime.to_iso8601()}"

    on_progress = opts[:on_progress] || fn _ -> :ok end

    with :ok <- validate_site_dir(site_dir),
         :ok <- validate_git_available(),
         {:ok, repo_url} <- resolve_repo_url(repo) do
      do_deploy(site_dir, repo_url, branch, message, on_progress)
    end
  end

  defp validate_site_dir(dir) do
    if File.exists?(Path.join(dir, "index.html")) do
      :ok
    else
      {:error, "No index.html found in #{dir}. Generate the site first."}
    end
  end

  defp validate_git_available do
    case System.cmd("git", ["--version"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      _ -> {:error, "git is not available on this system"}
    end
  end

  defp resolve_repo_url(repo) do
    cond do
      # Already a full URL
      String.starts_with?(repo, "https://") or String.starts_with?(repo, "git@") ->
        {:ok, repo}

      # Short form: owner/repo
      String.contains?(repo, "/") and not String.contains?(repo, " ") ->
        {:ok, "https://github.com/#{repo}.git"}

      true ->
        {:error, "Invalid repository: #{repo}. Use 'owner/repo' or a full git URL."}
    end
  end

  defp do_deploy(site_dir, repo_url, branch, message, on_progress) do
    # Work in the site directory
    git_opts = [cd: site_dir, stderr_to_stdout: true]

    steps = [
      {"Initializing git repository...", fn -> System.cmd("git", ["init"], git_opts) end},
      {"Configuring git...",
       fn ->
         System.cmd("git", ["config", "user.email", "emothe-deploy@noreply"], git_opts)
         System.cmd("git", ["config", "user.name", "EMOTHE Deploy"], git_opts)
       end},
      {"Staging files...", fn -> System.cmd("git", ["add", "-A"], git_opts) end},
      {"Creating commit...", fn -> System.cmd("git", ["commit", "-m", message], git_opts) end},
      {"Pushing to #{branch}...",
       fn ->
         System.cmd("git", ["push", "--force", repo_url, "HEAD:#{branch}"], git_opts)
       end}
    ]

    Enum.reduce_while(steps, :ok, fn {status, cmd_fn}, _acc ->
      on_progress.(status)

      case cmd_fn.() do
        {_output, 0} -> {:cont, :ok}
        {output, _code} -> {:halt, {:error, "Git error: #{String.trim(output)}"}}
      end
    end)
    |> case do
      :ok ->
        # Derive GitHub Pages URL
        url = derive_pages_url(repo_url)
        on_progress.("Deployed successfully!")
        {:ok, url}

      {:error, _} = err ->
        err
    end
  end

  defp derive_pages_url(repo_url) do
    # Extract owner/repo from URL
    cond do
      String.contains?(repo_url, "github.com") ->
        repo_url
        |> String.replace(~r{^https://github\.com/}, "")
        |> String.replace(~r{^git@github\.com:}, "")
        |> String.replace(~r{\.git$}, "")
        |> then(fn path ->
          case String.split(path, "/") do
            [owner, repo] -> "https://#{owner}.github.io/#{repo}/"
            _ -> repo_url
          end
        end)

      true ->
        repo_url
    end
  end
end
