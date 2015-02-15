require 'set'
require 'sprockets/utils'

module Sprockets
  # Internal: Bundle processor takes a single file asset and prepends all the
  # `:required` URIs to the contents.
  #
  # Uses pipeline metadata:
  #
  #   :required - Ordered Set of asset URIs to prepend
  #   :stubbed  - Set of asset URIs to substract from the required set.
  #
  # Also see DirectiveProcessor.
  class Bundle
    def self.call(input)
      env  = input[:environment]
      type = input[:content_type]
      dependencies = Set.new(input[:metadata][:dependencies])

      processed_uri, deps = env.resolve(input[:filename], accept: type, pipeline: "self", compat: false)
      dependencies.merge(deps)

      find_required = proc { |uri| env.load(uri).metadata[:required] }
      required = Utils.dfs(processed_uri, &find_required)
      stubbed  = Utils.dfs(env.load(processed_uri).metadata[:stubbed], &find_required)
      required.subtract(stubbed)
      assets = required.map { |uri| env.load(uri) }

      (required + stubbed).each do |uri|
        dependencies.merge(env.load(uri).metadata[:dependencies])
      end

      process_bundle_reducers(assets, env.load_bundle_reducers(type)).merge(dependencies: dependencies, included: assets.map(&:uri))
    end

    # Internal: Run bundle reducers on set of Assets producing a reduced
    # metadata Hash.
    #
    # assets - Array of Assets
    # reducers - Array of [initial, reducer_proc] pairs
    #
    # Returns reduced asset metadata Hash.
    def self.process_bundle_reducers(assets, reducers)
      initial = {}
      reducers.each do |k, (v, _)|
        initial[k] = v if v
      end

      assets.reduce(initial) do |h, asset|
        reducers.each do |k, (_, block)|
          value = k == :data ? asset.source : asset.metadata[k]
          h[k]  = h.key?(k) ? block.call(h[k], value) : value
        end
        h
      end
    end
  end
end
