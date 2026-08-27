# frozen_string_literal: true

Rails.application.routes.draw do
  mount SolidQueuePanel::Engine => "/solid_queue"

  root to: redirect("/solid_queue")
end
