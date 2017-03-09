require "github_commenter"

require "addressable/template"
require "git_diff_parser"
require "thor"
require "octokit"

module GithubCommenter
  class CLI < ::Thor
    class << self
      def github_pr_options
        option :from_env, enum: %w[ circleci ], description: "complete things from ENV variables of CI. override github,repo,pr,after,until"

        # github things
        option :github, description: "github API entry point (default: https://api.github.com/v3)"
        option :repo,   description: "respoitory of github e.g. okitan/github_commenter"
        option :pr, type: :numeric, description: "number of PR"

        option :github_access_token, required: true, default: ENV["GITHUB_ACCESS_TOKEN"]

        # comments
        option :after, description: "post comment when commits of inserting this line after this hash exist"
        option :until, description: "post comment when commits of inserting this line exists"
      end
    end

    desc "pr", "comment to pr"
    github_pr_options

    option :input_format, default: "ltsv", enum: %w[ ltsv ], description: "when stdin comes, it will be parsed according to this format"

    option :message, description: "when no stdin comes, we use this option as pr comment message"
    option :file,    description: "when no stdin comes, we use this option as target file of pr comment"
    option :line,    type: :numeric, description: "when no stdin comes, we use this option as line number in target file of pr comment (Note: this is not line in diff of pr)"

    option :debug, type: :boolean, descriptin: "if true, do not post pr comment"
    def pr
      @options, comments = parse_options

      post_pr_comments(filter_comments(comments, after: @options["after"], _until: @options["before"]))
    end

    protected
    def post_pr_comments(comments)
      base = pr_info.base.sha
      head = `git log -n 1 --pretty=%H`.chomp

      diff = GitDiffParser.parse(`git diff #{base}`)

      comments.each do |comment|
        patch_position = find_patch_position_of_comment(diff, comment)

        if @options["debug"]
          warn "PR comment to #{@options["repo"]}/pulls/#{@options["pr"]}@#{head}##{comment[:file]}:#{patch_position} => #{comment[:message]}"
        else
          github_client.create_pull_request_comment(@options["repo"], @options["pr"], comment[:message], head, comment[:file], patch_position)
        end
      end
    end

    def github_client
      @github_client ||= begin
        Octokit.configure {|config| config.api_endpoint = @options["github"] }
        Octokit::Client.new(access_token: @options["github_access_token"])
      end
    end

    def pr_info
      @pr_info ||= begin
        github_client.pull_request(@options["repo"], @options["pr"])
      end
    end

    def filter_comments(comments, after: nil, _until: nil)
      after ||= pr_info.base.sha

      # XXX: commandline injection risk
      diff = GitDiffParser.parse(`git diff #{after} #{_until}`) # when _until is nil it is treated as HEAD

      comments.select do |comment|
        if comment[:file]
          find_patch_position_of_comment(diff, comment)
        else # pr comment
          false # TODO: post to pr
        end
      end
    end

    def find_patch_position_of_comment(diff, comment)
      diff_of_file = diff.find {|f| f.file == comment[:file] }

      if diff_of_file
        line = diff_of_file.changed_lines.find {|line| line.number == comment[:line].to_i }

        return line.patch_position if line
      end

      nil
    end

    def parse_options
      comments = if stdin?
        parse_comments(File.read($stdin))
      else
        if options[:message] && options[:file] && options[:line]
          [ { message: options[:message], file: options[:file], line: options[:line] } ]
        else
          raise ::Thor::RequiredArgumentMissingError, "no comments found. gives stdin or use --message option"
        end
      end

      options = complete_options(self.options)

      return [ options, comments ]
    end

    def parse_comments(string)
      case options[:input_format]
      when "ltsv"
        require "ltsv"

        LTSV.parse(string).map do |line|
          line[:line] = line[:line].to_i if line[:line]
          line
        end
      else
        raise "unknown input format: #{options[:input_format]}"
      end
    end

    def complete_options(options)
      complete = case options[:from_env]
      when "circleci"
        completed_params_of_circleci(options)
      else
        {}
      end

      options.merge(complete)
    end

    def completed_params_of_circleci(options)
      if pr = ENV["CI_PULL_REQUEST"]
        pr_num = pr.split("/").last.to_i

        template = Addressable::Template.new("https://{host}/{organization}/{repository}/compare/{after}...{until}")

        if params = template.extract(ENV["CIRCLE_COMPARE_URL"])
          github = if params["host"] == "github.com"
            "https://api.github.com/v3"
          else
            "https://#{params["host"]}/api/v3" # I don't know this is correct
          end

          return {
            "github" => github,
            "repo"   => [ params["organization"], params["repository"] ].join("/"),
            "pr"     => pr_num,
            "after"  => params["after"],
            "until"  => params["until"]
          }
        else
          warn `env`
          raise "really?"
        end
      end

      {}
    end

    def stdin?
      # http://www.ownway.info/Ruby/idiom/judge_stdin
      File.pipe?($stdin) || File.select([$stdin], [], [], 0)
    end
  end
end
