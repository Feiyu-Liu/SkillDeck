# Run from any directory: ruby .github/tests/workflow_policy_test.rb
# Uses only Ruby's bundled YAML/JSON and Minitest (available on hosted Ubuntu).
require 'yaml'
require 'json'
require 'minitest/autorun'

class WorkflowPolicyTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  HOSTED = %w[ubuntu-24.04 macos-15 windows-2022].freeze

  def workflows
    Dir[File.join(ROOT, 'workflows', '*.yml')].to_h do |path|
      [File.basename(path), YAML.load_file(path)]
    end
  end

  def triggers(workflow)
    workflow.fetch('on') { workflow.fetch(true) }
  end

  def test_entrypoints_are_read_only_pr_and_main_verification
    assert_equal 6, workflows.size
    workflows.each do |name, workflow|
      assert_equal({'contents' => 'read'}, workflow.fetch('permissions'), name)
      events = triggers(workflow)
      assert_empty(events.keys - %w[pull_request push workflow_dispatch workflow_call], name)
      next if events.key?('workflow_call')

      assert events.key?('pull_request'), name
      assert_equal ['main'], events.fetch('push').fetch('branches'), name
      refute events.fetch('push').key?('tags'), name
      assert_equal "${{ github.event_name == 'pull_request' }}",
                   workflow.fetch('concurrency').fetch('cancel-in-progress'), name
      options = events.dig('workflow_dispatch', 'inputs', 'tier', 'options')
      assert_equal %w[quick merge], options if options
    end
  end

  def test_all_runner_assignments_resolve_to_standard_hosted_labels
    workflows.each do |name, workflow|
      workflow.fetch('jobs').each_value do |job|
        assert_equal({'contents' => 'read'}, job['permissions'], name) if job.key?('permissions')
        Array(job['steps']).each do |step|
          if step.fetch('uses', '').start_with?('actions/checkout@')
            assert_equal false, step.dig('with', 'persist-credentials'), name
          end
        end
        runner = job['runs-on'] || job.dig('with', 'runner')
        case runner
        when '${{ inputs.runner }}'
          assert triggers(workflow).key?('workflow_call'), name
        when '${{ matrix.runner }}'
          matrix = job.fetch('strategy').fetch('matrix')
          labels = if matrix['include']
                     matrix['include'].map { |row| row.fetch('runner') }
                   else
                     # These matrices select literal JSON lists, never runner variables.
                     expression = matrix.fetch('runner')
                     assert_match(/fromJSON\(github.event_name == 'pull_request'/, expression)
                     expression.scan(/'([^']*\[[^']*\])'/).flat_map { |match| JSON.parse(match.first) }
                   end
          refute_empty labels, name
          assert_empty(labels - HOSTED, name)
        else
          assert_includes HOSTED, runner, name
        end
      end
    end
  end

  def test_actions_are_pinned_and_no_credentials_or_private_runner_state_are_used
    files = workflows.values + [YAML.load_file(File.join(ROOT, 'actions/setup-ci/action.yml'))]
    visit = lambda do |node|
      case node
      when Hash
        node.each do |key, value|
          if key == 'uses' && !value.start_with?('./')
            assert_match(/\A[\w.-]+\/[\w.-]+@[a-f0-9]{40}\z/, value)
          end
          refute_equal 'secrets', key
          assert_equal false, value if key == 'persist-credentials'
          visit.call(value)
        end
      when Array
        node.each { |value| visit.call(value) }
      when String
        refute_match(/secrets\.|vars\.|self-hosted|use-preinstalled-flutter|export_macos_proxy|--release|tool\/release\.py|secrets: inherit/, node)
      end
    end
    files.each { |file| visit.call(file) }
  end

  def test_platform_and_verification_contracts
    app = workflows.fetch('skills-manager-ci.yml')
    matrix = app.dig('jobs', 'active-platforms', 'strategy', 'matrix', 'include')
    assert_equal %w[macos windows], matrix.map { |row| row.fetch('device') }
    workspace = workflows.fetch('skills-workspace-ci.yml')
    matrix = workspace.dig('jobs', 'platform-gates', 'strategy', 'matrix', 'include')
    assert_equal %w[linux macos windows], matrix.map { |row| row.fetch('device') }.sort
    platform_steps = workflows.fetch('skills-workspace-platform.yml').dig('jobs', 'verify', 'steps')
    commands = platform_steps.map { |step| step['run'] }.compact
    assert_includes commands, 'dart test -j 1 integration_test'
    assert_includes commands, 'dart run tool/check_coverage.dart coverage/lcov.info 85'
    assert commands.any? { |command| command.start_with?('xvfb-run -a flutter test') }
    translation = workflows.fetch('skills-translation-ci.yml').dig('jobs', 'minimum-sdk')
    assert_equal 2, translation.dig('strategy', 'matrix', 'package').length
    assert translation.fetch('steps').any? { |step| step.dig('with', 'flutter-version') == '3.29.3' }
    setup = YAML.load_file(File.join(ROOT, 'actions/setup-ci/action.yml'))
    assert_equal '3.50.0', setup.dig('inputs', 'flutter-version', 'default')
  end
end
