springAccelerationForState = (state) ->
	return - state.tension * state.x - state.friction * state.v

springEvaluateState = (initialState) ->

	output = {}
	output.dx = initialState.v
	output.dv = springAccelerationForState initialState

	return output

springEvaluateStateWithDerivative = (initialState, dt, derivative) ->

	state = {}
	state.x = initialState.x + derivative.dx * dt
	state.v = initialState.v + derivative.dv * dt
	state.tension = initialState.tension
	state.friction = initialState.friction

	output = {}
	output.dx = state.v
	output.dv = springAccelerationForState state

	return output

springIntegrateState = (state, speed) ->

	a = springEvaluateState state
	b = springEvaluateStateWithDerivative state, speed * 0.5, a
	c = springEvaluateStateWithDerivative state, speed * 0.5, b
	d = springEvaluateStateWithDerivative state, speed, c

	dxdt = 1.0/6.0 * (a.dx + 2.0 * (b.dx + c.dx) + d.dx)
	dvdt = 1.0/6.0 * (a.dv + 2.0 * (b.dv + c.dv) + d.dv)

	state.x = state.x + dxdt * speed
	state.v = state.v + dvdt * speed

	return state
