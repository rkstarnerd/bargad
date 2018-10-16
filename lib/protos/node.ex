# Copyright 2018 Faraz Haider. All Rights Reserved.
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

defmodule Bargad.Nodes do
  @moduledoc """
  Protobuf definition for a tree node.

  ```
  message Node {
  required bytes treeId = 1;
  required bytes hash = 2;
  repeated bytes children = 3;
  required int64 size = 4;
  optional bytes metadata = 5;
  optional bytes key = 6;
  }
  ```

  """
  @doc false
  @external_resource Path.expand("./node.proto", __DIR__)
  use Protobuf, from: Path.expand("./node.proto", __DIR__)
end
