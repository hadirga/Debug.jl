module TestGraft
export @syms
using Debug, Debug.AST, Debug.Eval
using Debug.Graft.instrument, Debug.is_trap, Debug.Meta.quot
import Debug.AST.is_emittable
export @test_graft

macro assert_fails(ex)
    quote
        if (try; $(esc(ex)); true; catch e; false; end)
            error($("@assert_fails: $ex didn't fail!"))
        end
    end
end

type Graft; ex; end
is_emittable(::Node{Graft}) = false

trap(::Any, ::Scope) = nothing
function trap(g::Node{Plain}, scope::Scope)
    g = exof(g)
    if isa(g, QuoteNode)
        g = g.value
        if isa(g, Node{Graft})
            debug_eval(scope, valueof(g).ex)
        end
    end
end

macro instrument_assume_global(trap_ex, ex)
    @gensym trap_var
    esc(quote
        const $trap_var = $trap_ex
        $(instrument(is_trap, trap_var, ex))
    end)
end

macro graft(ex)
    quot(Node(Graft(ex)))
end
macro test_graft(ex)
    :(@instrument_assume_global trap $(esc(ex)))
end


type T
    x
    y
end

@test_graft let
    # test read and write, both ways
    local x = 11
    @graft (@assert x == 11; x = 2)
    @assert x == 2
    
    # test tuple assignment in graft
    local y, z 
    @graft y, z = 12, 23 
    @assert (y, z) == (12, 23)
    
    # test updating operator in graft
    q = 3
    @graft q += 5
    @assert q == 8
    
    # test assignment to ref in graft (don't rewrite)
    a = [1:5;]
    @graft a[2]  = 45
    @graft a[3] += 1
    @assert isequal(a, [1,45,4,4,5])
    
    # test assignment to field in graft (don't rewrite)
    t = T(7,83)
    @graft t.x  = 71
    @graft t.y -= 2
    @assert (t.x == 71) && (t.y == 81)
    
    # test that k inside the grafted let block is separated from k outside
    k = 21
    @graft let k=5
        @assert k == 5
    end
    @assert k == 21
    
    # test that assignments to local vars don't leak out
    @graft let
        l = 3
    end
    
    # test that assignements to shared vars do leak out
    s = 1
    @graft let
        s = 6
    end
    @assert s == 6
end

@test_graft begin
    type TT
        x::Int
        function TT(x)
            local z
            @graft z=2x
            new(z)
        end
    end

    t = TT(42)
    @assert t.x == 84
end

@test_graft begin
    type TTT
        x::Int
        function TTT(x=11; m=1)
            local z
            @graft z=m*x
            new(z)
        end
    end

    t = TTT(m=3)
    @assert t.x == 33
end

@assert_fails @test_graft let
    @graft a = 3
end
@assert_fails @test_graft let
    @graft local d1 = 3
end
@assert_fails @test_graft let
    @graft local d2
end

end # module
