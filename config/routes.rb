# frozen_string_literal: true

AmarantosAcrt::Engine.routes.draw do
  get "/v1/health" => "v1#health"
  get "/v1/certification-state" => "v1#certification_state"
  get "/v1/users/:user_id/certification-state" => "v1#user_certification_state"
  get "/v1/users/:user_id/activity" => "v1#activity"
  post "/v1/users/:user_id/certification" => "v1#set_certification"
  delete "/v1/users/:user_id/certification" => "v1#clear_certification"
  post "/v1/migrate-group" => "v1#migrate_group"
  put "/v1/topics/:topic_id/related-guide" => "v1#set_related_guide"
  delete "/v1/topics/:topic_id/related-guide" => "v1#clear_related_guide"
  get "/v1/dormancy-candidates" => "v1#dormancy_candidates"
  post "/v1/users/:user_id/dormancy" => "v1#dormancy"
  delete "/v1/users/:user_id/dormancy" => "v1#reactivate"
  get "/v1/editorial-candidates" => "v1#editorial_candidates"
  post "/v1/configure-categories" => "v1#configure_categories"
end

Discourse::Application.routes.draw do
  mount ::AmarantosAcrt::Engine, at: "/amarantos-acrt"
end
