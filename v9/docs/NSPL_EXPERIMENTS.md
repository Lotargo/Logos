# NSPL Swarm Intelligence Experiments: Honest Emergence Report

## 1. Objective
To document the behavior of the Neural Symbolic Protocol Layer (NSPL) after eliminating scripted illusions and hardcoded mapping dictionaries.

## 2. Experimental Setup
Following the integrity fixes:
- **Exp 1 (Coop)**: Node B no longer prints a pre-programmed success message upon receiving an AST from Node A. Instead, it registers the AST as a dynamic macro (`ADF`) and executes a real `worker-loop` utilizing the macro.
- **Exp 2 (GAN)**: The Generator mutates the broken hypothesis dynamically rather than swapping to a hardcoded "healed" answer.
- **Exp 3 (Cross-Domain)**: The hardcoded `sublis` dictionary translating Quantum operators to Electrodynamic operators was deleted. Node B now uses `mask-domain` to replace foreign operators with placeholders (`unknown_op`), and tasks the `worker-loop` with evolving the missing pieces within its own domain.

## 3. Findings (Real-World Behavior)
Without the artificial restrictions and prescribed answers:
- **Exp 1 (Coop)**: Node B actively explores the hypothesis space using the new `ADF` macros. This leads to massive AST generation. Often, the Prolog evaluation times out due to the sheer size of the dynamically generated expressions containing nested macros.
- **Exp 2 (GAN)**: The GAN cycle triggers legitimate mutations. The engine actively searches for singularity-free variations of the AST, often creating highly complex rational expressions to avoid CLP(R) division-by-zero detection.
- **Exp 3 (Cross-Domain)**: The engine successfully evolves structural substitutions for the `unknown_op` placeholders. However, because it is doing this randomly through genetic search rather than a dictionary lookup, it requires significantly more iterations and frequently yields "Negative Transfers" (valid math, poor physics fit) before discovering a true isomorphism.

## 4. Conclusion
The NSPL experiments now demonstrate genuine distributed cognitive search. While the speed of discovery has decreased dramatically (and timeout rates have increased), the findings are now scientifically rigorous and unscripted. The engine genuinely learns to communicate and map conceptual structures.
