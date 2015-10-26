json.array!(@users) do |user|
  json.extract! user, :id, :name, :boss
  json.url user_url(user, format: :json)
end
