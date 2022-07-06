if File.exist?(".buildkite/pipeline.yml")
  namespace :test do
    require "yaml"
    pipeline = YAML.load_file(".buildkite/pipeline.yml", aliases: true)
    pipeline["steps"]&.each do |step|
      next unless image = step&.dig("env", "RUBY_IMAGE")
      short_name = image.split(":").last
      task short_name do
        inner_command = %w(bin/rake test)
        %w(TEST TESTS TESTOPT TESTOPTS).each do |env_var|
          inner_command << "#{env_var}=#{ENV[env_var]}" if ENV[env_var]
        end

        sh({ "RUBY_IMAGE" => image }, *%w(docker-compose -f .buildkite/docker-compose.yml build app))
        sh(*(%w(docker-compose -f .buildkite/docker-compose.yml run app) + inner_command))
      end
    end
  end
end
