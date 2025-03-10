collect_metrics :: (tc: Typechecked(Code_Procedure_Body)) -> (metrics: Metrics) {
    metrics: Metrics;

    my_file, my_module := get_file_and_module(tc.expression);

    if_depth := 0;
    max_if_depth := 0;
    loop_depth := 0;
    max_loop_depth := 0;
    
    if_stack: [..] *Code_If;
    
    visit_pre_and_postorder(tc.expression, #code {
        if it.kind == {
          case .IF;
            c := cast(*Code_If) it;

            is_else_if := false;

            parent: *Code_If;
            if preorder {
                if if_stack parent = peek(if_stack);
            } else {
                if if_stack.count > 1  parent = if_stack[if_stack.count-2];  // We ourselves are on top of the stack!
            }

            if parent && parent.else_block && (parent.else_block.statements.count == 1) {
                if parent.else_block.statements[0] == c {
                    is_else_if = true;
                }
            }
            
            if preorder  {
                // Add points based on whatever depth we are in currently. Right now,
                // it's just linear with depth. We do this before we increment the depth
                // so's we don't have to subtract 1!

                array_add(*if_stack, c);
                metrics.if_points += cast(s32) if_depth;

                
                if !is_else_if {
                    if_depth += 1;
                    max_if_depth = max(max_if_depth, if_depth);
                }
                
                if c.if_flags & .IS_SWITCH_STATEMENT {
                    // 1 + sqrt of the number of cases. This is highly debatable and
                    // I am sure we will revise it.
                    // (We count cases below, and add the score at the end.)
                    metrics.if_points += 1;
                } else {
                    // We say an ifx without an else is 1 point, with an else it's 2.
                    // A non-expression if is 2, or with an else, 3.
                    // Longer-term we should probably add a point for each nested indirection level,
                    // but we would need to do a recursive visit for that, so, not yet.
                    if c.if_flags & .IS_IFX {
                        metrics.if_points += 1;
                    } else {
                        metrics.if_points += 2;
                    }
                }
                
                if c.else_block {
                    metrics.if_points += 1;
                }       
            } else {
                popped := pop(*if_stack);
                assert(popped == c);
                
                if !is_else_if {
                    if_depth -= 1;
                }
            }
        
          case .WHILE;
            if preorder  { loop_depth += 1; max_loop_depth = max(max_loop_depth, loop_depth); }
            else         loop_depth -= 1;
          case .FOR;
            if preorder  { loop_depth += 1; max_loop_depth = max(max_loop_depth, loop_depth); }
            else         loop_depth -= 1;
        }
    });

    assert(if_stack.count == 0);
    
    if if_depth < 0  log_error("We did something very bad and produced an if_depth of %!\n", if_depth);
                            
    num_cases := 0;
    for tc.subexpressions {
        if it.kind == {
          case .IF;
/* This stuff is now accounted for in visit_pre_and_postorder above.
            c := cast(*Code_If) it;
            
            if c.is_switch_statement {
                // 1 + sqrt of the number of cases. This is highly debatable and
                // I am sure we will revise it.
                // (We count cases below, and add the score at the end.)
                metrics.if_points += 1;
            } else {
                // We say an ifx without an else is 1 point, with an else it's 2.
                // A non-expression if is 2, or with an else, 3.
                // Longer-term we should probably add a point for each nested indirection level,
                // but we would need to do a recursive visit for that, so, not yet.
                if c.is_ifx {
                    metrics.if_points += 1;
                } else {
                    metrics.if_points += 2;
                }
            }
            
            if c.else_block metrics.if_points += 1;
*/
          case .CASE;
            num_cases += 1;
            
          case .PROCEDURE_CALL;
            call := cast(*Code_Procedure_Call) it;
            resolved := call.resolved_procedure_expression;
            if resolved {
                if resolved.type.type != .TYPE {  // This is a type instantiation call. We should probably have the compiler flag these!
                    metrics.total_calls += 1;

                    other_file, other_module := get_file_and_module(resolved);
                    if other_file   == my_file    metrics.same_file_calls += 1;
                    if other_module == my_module  metrics.same_module_calls += 1;

                    if (other_module == basic_module) && (resolved.kind == .PROCEDURE_HEADER) {
                        header := cast(*Code_Procedure_Header) resolved;
                        if header.name == {
                            case "alloc";        metrics.allocations += 1;
                            case "Dynamic_New";  metrics.allocations += 1;
                            case "NewArray";     metrics.allocations += 1;
                            case "alloc_string"; metrics.allocations += 1;
                            case "copy_string";  metrics.allocations += 1;
                            case "free";         metrics.frees += 1;
                            case "realloc";      metrics.allocations += 1; metrics.frees += 1;
                            case "New";          metrics.allocations += 1;
                        }
                    }
                }
            } else {
                metrics.total_calls += 1;
                metrics.nonconstant_calls += 1;
            }
            
          case .BINARY_OPERATOR;
            op := cast(*Code_Binary_Operator) it;
            if op.operator_type == #char "=" {
                metrics.reassignments += 1;

                // @Incomplete: Categorize a wider variety of stuff as global writes?
                if op.left.kind == .IDENT {
                    if is_global_ident(cast(*Code_Ident) op.left) {
                        metrics.global_writes += 1;
                    }
                }
            }
            
          case .IDENT;
            ident := cast(*Code_Ident) it;
            if is_global_ident(ident) {
                metrics.global_reads += 1;
            }
        }
    }

    if num_cases {
        f := Math.sqrt(cast(float) num_cases);
        points := cast(s32) Math.floor(f + .5);
        metrics.if_points += points;
    }

    metrics.maximum_if_depth   = cast(s32) max_if_depth;
    metrics.maximum_loop_depth = cast(s32) max_loop_depth;
    
//    log("%: max_if_depth %\n", tc.expression.header.name, max_if_depth);

    return metrics;
}

get_file_and_module :: (node: *Code_Node) -> (file: *Message_File, import: *Message_Import) {
    if !node.enclosing_load return null, null;

    file := node.enclosing_load;

    if !file.enclosing_import return file, null;  // @Cleanup: Should not happen?
    return file, file.enclosing_import;
}
    
is_global_ident :: (ident: *Code_Ident) -> bool {
    if !ident.resolved_declaration return false;  // Uh, we don't know what this is, I guess.

    decl := ident.resolved_declaration;
    if decl.flags & .IS_CONSTANT return false;  // We do not worry about constants!

    return cast(bool) (decl.flags & .IS_GLOBAL);
}

Math   :: #import "Math";
