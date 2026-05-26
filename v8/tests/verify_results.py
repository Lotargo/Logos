import sys
import csv
import numpy as np

def parse_ast(expr_str):
    """
    Parses a simple Lisp AST string into a nested list structure.
    E.g., "(mul a (mul a a))" -> ['mul', 'a', ['mul', 'a', 'a']]
    """
    expr_str = expr_str.strip()
    if not expr_str.startswith('('):
        # Numeric constant or variable
        try:
            return float(expr_str)
        except ValueError:
            return expr_str
    
    # Tokenize parentheses and spaces
    tokens = []
    current_token = []
    for char in expr_str:
        if char == '(':
            tokens.append('(')
        elif char == ')':
            if current_token:
                tokens.append("".join(current_token))
                current_token = []
            tokens.append(')')
        elif char.isspace():
            if current_token:
                tokens.append("".join(current_token))
                current_token = []
        else:
            current_token.append(char)
            
    # Build tree
    stack = []
    current_list = []
    for token in tokens:
        if token == '(':
            stack.append(current_list)
            current_list = []
        elif token == ')':
            if stack:
                parent = stack.pop()
                parent.append(current_list)
                current_list = parent
        else:
            try:
                val = float(token)
                current_list.append(val)
            except ValueError:
                current_list.append(token)
                
    return current_list[0] if current_list else None

def evaluate_ast(ast, row_dict):
    """
    Evaluates parsed AST tree given a dictionary of variable values.
    """
    if isinstance(ast, (int, float)):
        return ast
    if isinstance(ast, str):
        # Variable lookup
        val = row_dict.get(ast)
        if val is None:
            # Maybe it is a string representation of a float
            try:
                return float(ast)
            except ValueError:
                raise ValueError(f"Unknown variable or symbol: {ast}")
        return val
    
    if not isinstance(ast, list) or len(ast) == 0:
        raise ValueError(f"Invalid AST element: {ast}")
        
    op = ast[0].lower()
    
    if op == 'add':
        return evaluate_ast(ast[1], row_dict) + evaluate_ast(ast[2], row_dict)
    elif op == 'sub':
        if len(ast) == 2:
            return -evaluate_ast(ast[1], row_dict)
        return evaluate_ast(ast[1], row_dict) - evaluate_ast(ast[2], row_dict)
    elif op == 'mul':
        return evaluate_ast(ast[1], row_dict) * evaluate_ast(ast[2], row_dict)
    elif op == 'div':
        denom = evaluate_ast(ast[2], row_dict)
        if denom == 0:
            return 1e9  # Avoid division by zero
        return evaluate_ast(ast[1], row_dict) / denom
    else:
        raise NotImplementedError(f"Operation {op} is not supported in verification yet.")

def verify_formula(csv_path, variables, formula_str):
    print(f"\n--- Independent Verification for Dataset: {csv_path} ---")
    print(f"Formula to evaluate: {formula_str}")
    
    # Load dataset
    data = []
    with open(csv_path, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if row:
                data.append([float(val) for val in row])
                
    data = np.array(data)
    num_vars = len(variables)
    
    inputs = data[:, :num_vars]
    targets = data[:, num_vars]
    
    # Parse Lisp AST
    ast = parse_ast(formula_str)
    
    predictions = []
    for row in inputs:
        row_dict = {variables[i]: row[i] for i in range(num_vars)}
        pred = evaluate_ast(ast, row_dict)
        predictions.append(pred)
        
    predictions = np.array(predictions)
    
    # Calculate Metrics
    mse = np.mean((targets - predictions) ** 2)
    variance = np.var(targets)
    r2 = 1 - (mse / variance) if variance != 0 else 1.0
    
    print(f"Mean Squared Error (MSE)           : {mse:.8f}")
    print(f"Coefficient of Determination (R^2) : {r2:.8f}")
    
    if r2 > 0.999 and mse < 1e-4:
        print("RESULT: VERIFICATION SUCCESSFUL! Formula matches target perfectly.")
    else:
        print("RESULT: VERIFICATION FAILED or contains discrepancies.")
        
    return mse, r2

if __name__ == '__main__':
    if len(sys.argv) < 4:
        print("Usage: python verify_results.py <csv_path> <comma_separated_vars> <lisp_formula>")
        sys.exit(1)
        
    csv_path = sys.argv[1]
    vars_list = sys.argv[2].split(',')
    formula = sys.argv[3]
    
    verify_formula(csv_path, vars_list, formula)
