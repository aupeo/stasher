FactoryGirl.define do
  factory :actioncontroller_payload, class: Hash do
    skip_create

    status 200
    format 'application/json'
    add_attribute('method', 'GET')
    path '/home?foo=bar'
    ip "127.0.0.1"
    params { {:controller => 'home', :action => 'index', 'foo' => 'bar' }.with_indifferent_access }
    db_runtime 0.02
    view_runtime 0.01

    initialize_with { attributes }
  end

  factory :activerecord_sql_payload, class: Hash do
    skip_create

    sql "SELECT * FROM `users` WHERE `users`.`id` = 5"
    name 'User Load'

    initialize_with { attributes }
  end
end