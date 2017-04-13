# TODO: tests with multiD variables

using PDMP, Base.Test

srand(1234)

p     = 2
P1    = randn(p)
P1   *= P1'
mu    = zeros(p)
mvg   = PDMP.MvGaussianCanon(mu,P1)
chain = chaingraph([ Factor( (x,v)->PDMP.nextevent_bps(mvg, x, v),
                              x   ->PDMP.gradloglik(mvg, x),
                              i) for i in 1:3])

srand(1234)

# test_local_definegraph defines a chain.
nvars = chain.structure.nvars
x0    = randn(nvars)
v0    = randn(nvars)
v0   /= norm(v0)
T     = abs(randn())

### TEST LOCALSIMULATION
v0a = randn(nvars+1)
x0a = randn(nvars-1)
@test_throws AssertionError LocalSimulation(chain,x0,v0a,T, 1000, 0.01)
@test_throws AssertionError LocalSimulation(chain,x0a,v0,T, 1000, 0.01)
@test_throws AssertionError LocalSimulation(chain,x0,v0,-0.1,1000,0.01)
@test_throws AssertionError LocalSimulation(chain,x0,v0,T,-10,0.01)
@test_throws AssertionError LocalSimulation(chain,x0,v0,T,1000,-0.1)

ls = LocalSimulation(chain,x0,v0,T,1000,0.001)
@test ls.x0==x0 && ls.v0==v0 && ls.T==T && ls.maxnevents==1000 &&
        ls.lambdaref==0.001 && ls.fg.structure.flist==chain.structure.flist

### TEST LS_RESHAPE
v = Vector{AllowedVarType}(5)
v = [randn(), randn(7), randn(), randn(50), randn(10)]
w = Vector{AllowedVarType}(5)
for i in 1:length(v)
    w[i] = v[i]*0.
end
u = vcat(v...)

@test ls_reshape(u, w) == v

all_evlist = AllEventList(Float, nvars)

for i in 1:nvars
    evi = Event(x0[i], v0[i], 0.0)
    pushevent!(all_evlist.evl[i], evi)
end

i   = rand(1:nvars)
j   = rand(1:nvars)
k   = rand(1:nvars)
t   = rand()
t1  = t+rand()
t2  = t1+rand()
t3  = t2+rand()
ev1 = Event(randn(), randn(), t1)
ev2 = Event(randn(), randn(), t2)
ev3 = Event(randn(), randn(), t3)
pushevent!(all_evlist.evl[i], ev1)
pushevent!(all_evlist.evl[j], ev2)
pushevent!(all_evlist.evl[k], ev3)

### Testing LS_RETRIEVE (1D) (without reflection)
fidx = 1
t    = t3+rand()
(xf, vf, g, vars) = ls_retrieve(chain, fidx, all_evlist, t, false)
aev1x = all_evlist.evl[1].xs[end]
aev1t = all_evlist.evl[1].ts[end]
aev1v = all_evlist.evl[1].vs[end]
aev2x = all_evlist.evl[2].xs[end]
aev2t = all_evlist.evl[2].ts[end]
aev2v = all_evlist.evl[2].vs[end]

@test   vars == [1,2] &&
        isapprox(vcat(xf...), [aev1x+(t-aev1t)*aev1v; aev2x+(t-aev2t)*aev2v]) &&
        isapprox(vcat(vf...), [aev1v; aev2v]) &&
        isapprox(g, chain.factors[fidx].gll(vcat(xf...)))

### Testing LS_RETRIEVE (1D) (with reflection)
fidx = 2
(xf, vf, g, vars) = ls_retrieve(chain, fidx, all_evlist, t, true)
aev1x = all_evlist.evl[2].xs[end]
aev1t = all_evlist.evl[2].ts[end]
aev1v = all_evlist.evl[2].vs[end]
aev2x = all_evlist.evl[3].xs[end]
aev2t = all_evlist.evl[3].ts[end]
aev2v = all_evlist.evl[3].vs[end]

@test   vars == [2,3] &&
        isapprox(vcat(xf...), [aev1x+(t-aev1t)*aev1v; aev2x+(t-aev2t)*aev2v]) &&
        isapprox(vcat(vf...), reflect_bps!(g, vcat(aev1v, aev2v))) &&
        isapprox(g, chain.factors[fidx].gll(vcat(xf...)))

### Testing LS_SAVEUPDATE!
ls_saveupdate!(all_evlist, vars, xf, vf, t)
ii = rand(1:length(vars))
vi = vars[ii]

@test getlastevent(all_evlist.evl[vi]) == Event(xf[ii], vf[ii], t)

### Testing LS_UPDATEPQ!
pq = PDMP.PriorityQueue()
srand(123); ls_updatepq!(pq, chain, fidx, xf, vf, g, t)
# It's gaussian so no need for thinning
srand(123); bounce = chain.factors[fidx].nextevent(vcat(xf...), vcat(vf...))

@test pq[fidx] == t+bounce.tau

### Testing LS_RANDOM
evl1 = EventList{Float}()
push!(evl1.xs, randn())
push!(evl1.vs, randn())
push!(evl1.ts, abs(randn()))

evl2 = EventList{Vector{Float}}()
push!(evl2.xs, randn(2))
push!(evl2.vs, randn(2))
push!(evl2.ts, abs(randn()))

srand(321); a1 = ls_random(evl1)
srand(321); a2 = ls_random(evl2)
srand(321); aa = randn()
srand(321); ab = randn(2)

@test a1==aa && a2==ab

### Testing LS_REFRESHMENT
t  = randexp()

srand(123)

pq = ls_refreshment(chain, t, all_evlist)

srand(123)

### this is a bit of a silly test but ls_refreshment is the
# composite of functions that have all been tested, so there's not much
# else to test than to just check it "works"
v = Vector{AllowedVarType}(chain.structure.nvars)
for i in 1:length(v)
    v[i] = ls_random(all_evlist.evl[i])
end
pq2 = PDMP.PriorityQueue(Int,Float)
for fidx in 1:chain.structure.nfactors
    (xf, vf, g, vars) = ls_retrieve(chain, fidx, all_evlist, t)
    ls_updatepq!(pq2, chain, fidx, xf, v[vars], g, t)
end

@test pq == pq2
