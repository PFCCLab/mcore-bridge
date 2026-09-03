#!/usr/bin/env bash

# Copyright (c) 2026 PaddlePaddle Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e
export bridge_dir=/workspace/mcore-bridge
mkdir -p /workspace/build_logs
export log_path=/workspace/build_logs
mkdir -p /workspace/upload
upload_path=/workspace/upload

python -m pip config --user set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
python -m pip config --user set global.trusted-host pypi.tuna.tsinghua.edu.cn

bridge_tar (){
    cd /workspace
    # mcore-bridge.tar only include the main branch
    if [ -n "$TARGET_COMMIT" ]; then
        echo "TARGET_COMMIT=$TARGET_COMMIT specified, skip refreshing mcore-bridge.tar.gz"
    elif [ -n "$BRANCH" ] && [ "$BRANCH" = "main" ]; then
        echo "Checkout branch $BRANCH"
        tar -zcf mcore-bridge.tar.gz mcore-bridge/
        mv mcore-bridge.tar.gz ${upload_path}/
    else
        echo "No BRANCH specified, skip checkout"
    fi
}

bridge_build (){
    cd $bridge_dir
    rm -rf build/
    rm -rf dist/
    rm -rf mcore_bridge.egg-info/

    python -m pip install -r requirements.txt
    python setup.py sdist bdist_wheel

    echo "install_mcore_bridge_develop_whl"
    python -m pip install --upgrade pip
    python -m pip install --ignore-installed dist/mcore_bridge-*.whl --no-cache-dir --force-reinstall --no-dependencies

    # importing mcore_bridge pulls in torch / megatron.core / transformer_engine,
    # which may be unavailable in a pure build image, so read the version from the
    # installed package metadata instead and only warn if the real import fails.
    echo "waiting for import mcore_bridge..."
    version=$(python -c "import importlib.metadata as m; print(m.version('mcore_bridge'))")
    echo "mcore_bridge version: ${version}"
    echo "mcore_bridge version: ${version}" >> ${log_path}/commit_info.txt
    python -c "import mcore_bridge; print('mcore_bridge import ok:', mcore_bridge.__version__)" \
        || echo "WARNING: import mcore_bridge failed (missing runtime deps in build image)"

    commit=${COMMIT_ID:-unknown}
    commit=${commit:0:7}

    whl_file=$(ls $bridge_dir/dist/mcore_bridge-*.whl)
    base_name=$(basename $whl_file)
    new_name=$(echo $base_name | sed "s/\.dev0/&+${commit}/")
    echo "commit whl: $new_name"
    cp "$whl_file" "${upload_path}/${new_name}"

    zero_name=$(echo $base_name | sed "s/^mcore_bridge-[^-]*-/mcore_bridge-0.0.0-/")
    if [ "${UPDATE_LATEST:-true}" = "true" ]; then
        echo "latest whl: $base_name"
        cp "$whl_file" "${upload_path}/${base_name}"
        echo "0.0.0 whl: $zero_name"
        cp "$whl_file" "${upload_path}/${zero_name}"
    else
        echo "UPDATE_LATEST=${UPDATE_LATEST}, skip latest whl: ${base_name} and 0.0.0 whl"
    fi
}

# main
cd ${bridge_dir}
echo -e "\033[32m ---- make mcore-bridge.tar.gz  \033[0m"
bridge_tar
echo -e "\033[32m ---- build mcore-bridge whl  \033[0m"
bridge_build
