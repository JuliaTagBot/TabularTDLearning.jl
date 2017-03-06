type SARSALambdaSolver <: Solver
   n_episodes::Int64
   max_episode_length::Int64
   learning_rate::Float64
   exploration_policy::Policy
   Q_vals::Matrix{Float64}
   eligibility::Matrix{Float64}
   lambda::Float64
   eval_every::Int64
   n_eval_traj::Int64
   function SARSALambdaSolver(mdp::Union{MDP,POMDP};
                            rng=Base.GLOBAL_RNG,
                            n_episodes=100,
                            max_episode_length=100,
                            learning_rate=0.001,
                            lambda=0.5,
                            exp_policy=EpsGreedyPolicy(mdp, 0.5),
                            eval_every=10,
                            n_eval_traj=20)
    return new(n_episodes, max_episode_length, learning_rate, 
               exp_policy, exp_policy.val.value_table,
               zeros(size(exp_policy.val.value_table)), lambda, eval_every, n_eval_traj)
    end
end


function create_policy(solver::SARSALambdaSolver, mdp::Union{MDP,POMDP})
    return solver.exploration_policy.val
end

function solve(solver::SARSALambdaSolver, mdp::Union{MDP,POMDP}, policy=create_policy(solver, mdp))
    rng = solver.exploration_policy.uni.rng
    Q = solver.Q_vals
    ecounts = solver.eligibility
    exploration_policy = solver.exploration_policy
    sim = RolloutSimulator(rng=rng, max_steps=solver.max_episode_length)

    for i = 1:solver.n_episodes
        s = initial_state(mdp, rng)
        a = action(exploration_policy, s)
        t = 0
        while !isterminal(mdp, s) && t < solver.max_episode_length
            sp, r = generate_sr(mdp, s, a, rng)
            ap = action(exploration_policy, sp)
            si = state_index(mdp, s); ai = action_index(mdp, a); spi = state_index(mdp, sp)
            api = action_index(mdp, ap)
            delta = r + discount(mdp) * Q[spi,api] - Q[si,ai]
            ecounts[si,ai] += 1
            for es in iterator(states(mdp))
                for ea in iterator(actions(mdp))
                    esi, eai = state_index(mdp, es), action_index(mdp, ea)
                    Q[esi,eai] += solver.learning_rate * delta * ecounts[esi,eai]
                    ecounts[esi,eai] *= discount(mdp) * solver.lambda
                end
            end
            s, a = sp, ap
            t += 1
        end
        if i % solver.eval_every == 0
            r_tot = 0.0
            for traj in 1:solver.n_eval_traj 
                r_tot += simulate(sim, mdp, policy, initial_state(mdp, rng))
            end
            println("On Iteration $i, Returns: $(r_tot/solver.n_eval_traj)")
        end
    end
    return policy 
end
