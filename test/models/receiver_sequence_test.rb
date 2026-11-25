require "test_helper"

class ReceiverSequenceTest < ActiveSupport::TestCase
  test "sequence statuses and delays execute in configured order" do
    setting = ReceiverSetting.for_route("custom")
    setting.update!(
      response_mode: "sequence",
      sequence_index: 0
    )
    setting.set_sequence_steps([
      { status_code: 500, delay_seconds: 0, response_body: "error 1" },
      { status_code: 503, delay_seconds: 1, response_body: "unavailable" },
      { status_code: 200, delay_seconds: 0, response_body: "ok" }
    ])
    setting.save!

    res1 = setting.resolve_next_response!
    assert_equal 500, res1[:status_code]
    assert_equal 0, res1[:delay_seconds]
    assert_equal "error 1", res1[:response_body]
    assert_equal 1, res1[:scenario_step]
    assert_not res1[:repeating]

    res2 = setting.resolve_next_response!
    assert_equal 503, res2[:status_code]
    assert_equal 1, res2[:delay_seconds]
    assert_equal "unavailable", res2[:response_body]
    assert_equal 2, res2[:scenario_step]
    assert_not res2[:repeating]

    res3 = setting.resolve_next_response!
    assert_equal 200, res3[:status_code]
    assert_equal 0, res3[:delay_seconds]
    assert_equal "ok", res3[:response_body]
    assert_equal 3, res3[:scenario_step]
  end

  test "final sequence step repeats indefinitely" do
    setting = ReceiverSetting.for_route("custom")
    setting.update!(response_mode: "sequence", sequence_index: 0)
    setting.set_sequence_steps([
      { status_code: 500, delay_seconds: 0 },
      { status_code: 200, delay_seconds: 0 }
    ])
    setting.save!

    setting.resolve_next_response! # step 1 -> 500
    res2 = setting.resolve_next_response! # step 2 -> 200
    assert_equal 200, res2[:status_code]
    assert_equal 2, res2[:scenario_step]

    # Subsequent requests should repeat step 2
    res3 = setting.resolve_next_response!
    assert_equal 200, res3[:status_code]
    assert_equal 2, res3[:scenario_step]
    assert res3[:repeating]

    res4 = setting.resolve_next_response!
    assert_equal 200, res4[:status_code]
    assert_equal 2, res4[:scenario_step]
    assert res4[:repeating]
  end

  test "reset resumes sequence at step 1" do
    setting = ReceiverSetting.for_route("custom")
    setting.update!(response_mode: "sequence", sequence_index: 0)
    setting.set_sequence_steps([
      { status_code: 500, delay_seconds: 0 },
      { status_code: 200, delay_seconds: 0 }
    ])
    setting.save!

    setting.resolve_next_response! # step 1
    setting.resolve_next_response! # step 2

    # Reset
    setting.reset_sequence_progress!
    setting.reload
    assert_equal 0, setting.sequence_index

    # Next call should be step 1 again
    res = setting.resolve_next_response!
    assert_equal 500, res[:status_code]
    assert_equal 1, res[:scenario_step]
  end

  test "two routes keep completely independent sequence progress" do
    route_a = ReceiverSetting.for_route("failure")
    route_b = ReceiverSetting.for_route("slow")

    route_a.update!(response_mode: "sequence", sequence_index: 0)
    route_a.set_sequence_steps([
      { status_code: 500, delay_seconds: 0 },
      { status_code: 200, delay_seconds: 0 }
    ])
    route_a.save!

    route_b.update!(response_mode: "sequence", sequence_index: 0)
    route_b.set_sequence_steps([
      { status_code: 429, delay_seconds: 0 },
      { status_code: 200, delay_seconds: 0 }
    ])
    route_b.save!

    # Advance route_a to step 2
    route_a.resolve_next_response! # Step 1: 500
    res_a2 = route_a.resolve_next_response! # Step 2: 200
    assert_equal 200, res_a2[:status_code]
    assert_equal 2, res_a2[:scenario_step]

    # Route B should still be at step 1!
    route_b.reload
    assert_equal 0, route_b.sequence_index
    res_b1 = route_b.resolve_next_response!
    assert_equal 429, res_b1[:status_code]
    assert_equal 1, res_b1[:scenario_step]
  end

  test "sequence step count clamps to maximum 20 steps" do
    setting = ReceiverSetting.for_route("custom")
    thirty_steps = (1..30).map { |i| { status_code: 200, delay_seconds: 0 } }
    setting.set_sequence_steps(thirty_steps)

    assert_equal 20, setting.parsed_steps.size
  end
end

