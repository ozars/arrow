@rem Licensed to the Apache Software Foundation (ASF) under one
@rem or more contributor license agreements.  See the NOTICE file
@rem distributed with this work for additional information
@rem regarding copyright ownership.  The ASF licenses this file
@rem to you under the Apache License, Version 2.0 (the
@rem "License"); you may not use this file except in compliance
@rem with the License.  You may obtain a copy of the License at
@rem
@rem   http://www.apache.org/licenses/LICENSE-2.0
@rem
@rem Unless required by applicable law or agreed to in writing,
@rem software distributed under the License is distributed on an
@rem "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
@rem KIND, either express or implied.  See the License for the
@rem specific language governing permissions and limitations
@rem under the License.

@rem To run the script:
@rem verify-release-candidate.bat VERSION RC_NUM

@echo on

if not exist "C:\tmp\" mkdir C:\tmp
if exist "C:\tmp\arrow-verify-release" rd C:\tmp\arrow-verify-release /s /q
if not exist "C:\tmp\arrow-verify-release" mkdir C:\tmp\arrow-verify-release

set _VERIFICATION_DIR=C:\tmp\arrow-verify-release
set _VERIFICATION_DIR_UNIX=C:/tmp/arrow-verify-release
set _VERIFICATION_CONDA_ENV=%_VERIFICATION_DIR%\conda-env
set _DIST_URL=https://dist.apache.org/repos/dist/dev/arrow
set _TARBALL=apache-arrow-%1.tar.gz
set ARROW_SOURCE=%_VERIFICATION_DIR%\apache-arrow-%1
set INSTALL_DIR=%_VERIFICATION_DIR%\install

@rem Requires GNU Wget for Windows
wget --no-check-certificate -O %_TARBALL% %_DIST_URL%/apache-arrow-%1-rc%2/%_TARBALL% || exit /B

tar xf %_TARBALL% -C %_VERIFICATION_DIR_UNIX%

set PYTHON=3.6

@rem Using call with conda.bat seems necessary to avoid terminating the batch
@rem script execution
call conda create -p %_VERIFICATION_CONDA_ENV% ^
    --no-shortcuts -f -q -y python=%PYTHON% ^
    || exit /B

call activate %_VERIFICATION_CONDA_ENV% || exit /B

call conda install -y ^
     --no-shortcuts ^
     python=3.7 ^
     git ^
     --file=ci\conda_env_cpp.yml ^
     --file=ci\conda_env_python.yml ^
     -c conda-forge || exit /B

set GENERATOR=Visual Studio 14 2015 Win64
set CONFIGURATION=release

pushd %ARROW_SOURCE%

set ARROW_HOME=%INSTALL_DIR%
set PARQUET_HOME=%INSTALL_DIR%
set PATH=%INSTALL_DIR%\bin;%PATH%

@rem Build and test Arrow C++ libraries
mkdir %ARROW_SOURCE%\cpp\build
pushd %ARROW_SOURCE%\cpp\build

@rem This is the path for Visual Studio Community 2017
call "C:\Program Files (x86)\Microsoft Visual Studio\2017\Community\Common7\Tools\VsDevCmd.bat" -arch=amd64

cmake -G "Ninja" ^
      -DCMAKE_INSTALL_PREFIX=%ARROW_HOME% ^
      -DARROW_BUILD_STATIC=OFF ^
      -DARROW_BOOST_USE_SHARED=ON ^
      -DARROW_BUILD_TESTS=ON ^
      -DGTest_SOURCE=BUNDLED ^
      -DCMAKE_BUILD_TYPE=%CONFIGURATION% ^
      -DARROW_CXXFLAGS="/MP" ^
      -DARROW_FLIGHT=ON ^
      -DARROW_PYTHON=ON ^
      -DARROW_PARQUET=ON ^
      ..  || exit /B

@rem NOTE(wesm): Building googletest is flaky for me with ninja. Building it
@rem first fixes the problem
ninja googletest_ep || exit /B

ninja install || exit /B

@rem Get testing datasets for Parquet unit tests
git clone https://github.com/apache/parquet-testing.git %_VERIFICATION_DIR%\parquet-testing
set PARQUET_TEST_DATA=%_VERIFICATION_DIR%\parquet-testing\data

git clone https://github.com/apache/arrow-testing.git %_VERIFICATION_DIR%\arrow-testing
set ARROW_TEST_DATA=%_VERIFICATION_DIR%\arrow-testing\data

@rem Needed so python-test.exe works
set PYTHONPATH=%CONDA_PREFIX%\Lib;%CONDA_PREFIX%\Lib\site-packages;%CONDA_PREFIX%\python35.zip;%CONDA_PREFIX%\DLLs;%CONDA_PREFIX%;%PYTHONPATH%

ctest -VV  || exit /B
popd

@rem Build and import pyarrow
pushd %ARROW_SOURCE%\python

set PYARROW_WITH_FLIGHT=1
set PYARROW_WITH_PARQUET=1
python setup.py build_ext --inplace --bundle-arrow-cpp bdist_wheel  || exit /B
py.test pyarrow -v -s --parquet || exit /B

popd

call deactivate
