# MACI-aMACI-circuits-build

## How to use

### Circuit

- `external/a-maci-evm`: aMACI circuits
- `external/vota-circuits/circuits/maci/power`: MACI circuits

### Compile circuit script

- `start_compile_amaci`: compile amaci circuit into zkey and wasm
- `start_compile_maci`: compile maci circuit into zkey and wasm

### How to run test data

- `js/amaci.test.js`: generate aMACI test data
- `js/maci.test.js`: generate MACI test data

### Start

1. First, determine whether to compile aMACI or MACI (enter the corresponding circuit directory) and install the corresponding dependencies
    ```shell
    npm i
    ```
2. Determine the circuit scale to be compiled
3. Modify the parameter settings of the corresponding circuit (2-1-1-5/4-2-2-25/...)
4. If it's aMACI, execute start_compile_amaci script; if it's MACI, execute start_compile_maci script (important data generated here will be in input/logs.json)
    ```shell
    ./start_compile_maci.sh 2-1-1-5
    ./start_compile_amaci.sh 2-1-1-5
    ```
5. After execution is complete, test data needs to be generated. If it's aMACI, execute js/amaci.test.js; if it's MACI, execute js/maci.test.js
    ```shell
    node js/amaci.test.js
    node js/maci.test.js
    ```
