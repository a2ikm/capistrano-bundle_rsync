require 'capistrano/bundle_rsync/scm'
require 'capistrano/configuration/filter'

class Capistrano::BundleRsync::Git < Capistrano::BundleRsync::SCM
  def check
    exit 1 unless execute("git ls-remote #{repo_url}")
    execute("mkdir -p #{config.local_base_path}")
  end

  def clone
    if File.exist?(config.local_mirror_path)
      info t(:mirror_exists, at: config.local_mirror_path)
    else
      if depth = fetch(:git_clone_depth)
        execute :git, :clone, '--recursive', '--depth', depth, repo_url, config.local_mirror_path
      else
        execute :git, :clone, '--recursive', repo_url, config.local_mirror_path
      end
    end
  end

  def update
    within config.local_mirror_path do
      execute :git, :remote, :update
      execute :git, :checkout, fetch(:branch)
      execute :git, :pull
      execute :git, :submodule, :update, '--init'
    end
  end

  def create_release
    execute "mkdir -p #{config.local_release_path}"

    if repo_tree = fetch(:repo_tree)
      repo_tree = repo_tree.slice %r#^/?(.*?)/?$#,  1 # strip both side /

      if strip_repo_tree = fetch(:strip_repo_tree, false)
        build_from = File.join(config.local_mirror_path, repo_tree, "")
      else
        build_from = File.join(config.local_mirror_path, repo_tree)
      end
    else
      build_from = File.join(config.local_mirror_path, "")
    end

    cmd = [:rsync, '-al', build_from, config.local_release_path].flatten
    execute *cmd
  end

  def rsync_release
    hosts = ::Capistrano::Configuration.env.filter(release_roles(:all))
    rsync_options = config.rsync_options
    Parallel.each(hosts, in_threads: config.max_parallels(hosts)) do |host|
      ssh = config.build_ssh_command(host)
      execute :rsync, "#{rsync_options} --rsh='#{ssh}' #{config.local_release_path}/ #{host}:#{release_path}/"
    end
  end

  def set_current_revision
    within config.local_mirror_path do
      set :current_revision, capture(:git, "rev-parse --short #{fetch(:branch)}")
    end
  end
end
