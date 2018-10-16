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

defmodule Bargad.Merkle do

  use Bitwise

  alias Bargad.{Types, Utils}

  @spec new(Types.tree_type, binary, Types.hash_algorithm, Types.backend) :: Types.tree
  def new(tree_type, tree_name, hash_function, backend) do
    tree = Utils.make_tree(tree_type, tree_name, hash_function, backend)
    tree = Utils.get_backend_module(backend).init_backend(tree)
    # put an empty leaf to make hash not nil (proto def says it's required), make the size zero
    tree |> Map.put(:root, Utils.make_hash(tree, <<>>)) |> Map.put(:size, 0)
  end

  @spec build(Types.tree, Types.values) :: Types.tree
  def build(tree, data) do
    # See this https://elixirforum.com/t/transform-a-list-into-an-map-with-indexes-using-enum-module/1523
    # Doing this to associate each value with it's insertion point.
    data = 1..length(data) |> Enum.zip(data) |> Enum.into([])
    tree |> Map.put(:root, do_build(tree, data).hash) |> Map.put(:size, length(data))
  end

  defp do_build(tree, [{index, value} | []]) do
    node = Utils.make_node(tree, Utils.make_hash(tree, index |> Integer.to_string |> Utils.salt_node(value)), [], 1, value)
    Utils.set_node(tree, node.hash, node)
    node
  end

  defp do_build(tree, data) do
    n = length(data)
    k = Utils.closest_pow_2(n)
    left_child = do_build(tree, Enum.slice(data, 0..(k - 1)))
    right_child = do_build(tree, Enum.slice(data, k..(n - 1)))

    node = Utils.make_node(
      tree,
      Utils.make_hash(tree, left_child.hash <> right_child.hash),
      [left_child.hash, right_child.hash],
      left_child.size + right_child.size,
      nil
    )

    Utils.set_node(tree, node.hash, node)
    node
  end

  @spec build(Types.tree, pos_integer) :: Types.audit_proof
  def audit_proof(tree = %Bargad.Trees.Tree{root: root, size: 1}, m) do
    root = Utils.get_node(tree, root)
    if m == 1 do
      %{value: root.metadata, proof: [], hash: root.hash}
    else
      raise "value out of range"
    end
  end

  @spec build(Types.tree, pos_integer) :: Types.audit_proof
  def audit_proof(tree, m) do
    #check left and right subtree, go wherever the value is closer
    if m > tree.size || m <= 0 do
      raise "value not in range"
    else
      root = Utils.get_node(tree, tree.root)
      [{value, hash} | proof] = tree |> do_audit_proof(nil, nil, root, m) |> Enum.reverse
      %{value: value, hash: hash, proof: proof}
    end
  end

  defp do_audit_proof(tree, nil, nil, %Bargad.Nodes.Node{children: [left , right], size: size}, m) do
    l = size |> :math.log2() |> :math.ceil() |> trunc

    left =  Utils.get_node(tree, left)
    right = Utils.get_node(tree, right)

    if m <= (1 <<< (l - 1)) do
      do_audit_proof(tree, right, "R", left, m)
    else
      do_audit_proof(tree, left, "L", right, m - (1 <<< (l - 1)))
    end
  end

  defp do_audit_proof(tree, sibling, direction, %Bargad.Nodes.Node{children: [left , right], size: size}, m) do
    l = size |> :math.log2() |> :math.ceil() |> trunc

    left =  Utils.get_node(tree, left)
    right = Utils.get_node(tree, right)

    if m <= (1 <<< (l - 1)) do
      [{sibling.hash, direction} | do_audit_proof(tree, right, "R", left, m)]
    else
      [{sibling.hash, direction} | do_audit_proof(tree, left, "L", right, m - (1 <<< (l - 1)))]
    end

  end

  defp do_audit_proof(_, sibling, direction, %Bargad.Nodes.Node{hash: salted_hash, children: [], metadata: value}, _) do
    [{sibling.hash, direction}, {value, salted_hash}]
  end

  @spec verify_audit_proof(Types.tree, Types.audit_proof) :: boolean
  def verify_audit_proof(tree, proof) do
    if tree.root == do_verify_audit_proof(proof.hash, proof.proof, tree) do
      true
    else
      false
    end
  end

  defp do_verify_audit_proof(leaf_hash, [], _) do
    leaf_hash
  end

  defp do_verify_audit_proof(leaf_hash, [{hash, direction} | t], tree) do
    case direction do
      "L" -> tree |> Utils.make_hash(hash <> leaf_hash) |> do_verify_audit_proof(t, tree)
      "R" -> tree |> Utils.make_hash(leaf_hash <> hash) |> do_verify_audit_proof(t, tree)
    end
  end

  @spec consistency_proof(Types.tree, pos_integer) :: Types.consistency_proof
  def consistency_proof(tree = %Bargad.Trees.Tree{root: root}, m) do
    root = Utils.get_node(tree, root)
    l = :math.ceil(:math.log2(root.size))
    t = trunc(:math.log2(m))
    do_consistency_proof(tree, nil, root, {l, t, m, root.size})
  end

  defp do_consistency_proof(tree, sibling, %Bargad.Nodes.Node{hash: hash}, {l, t, m, _}) when l == t do
    size = trunc(:math.pow(2, l))
    m = m - trunc(:math.pow(2, l))
    case m do
      0 -> [hash]
      _ -> l = :math.ceil(:math.log2(size))
        t = trunc(:math.log2(m))
        [hash | do_consistency_proof(tree, nil, sibling, {l, t, m, size})]
    end
  end

  defp do_consistency_proof(_, _, %Bargad.Nodes.Node{hash: hash, children: []}, _) do
    [hash]
  end

  defp do_consistency_proof(tree, _, %Bargad.Nodes.Node{children: [left , right]}, {l, t, m, size}) do
    left = Utils.get_node(tree, left)
    right = Utils.get_node(tree, right)
    do_consistency_proof(tree, right, left, {l - 1, t, m, size})
  end

  @spec verify_consistency_proof(Types.tree, Types.consistency_proof, binary) :: binary
  def verify_consistency_proof(tree, proof, old_root_hash) do
    hash = do_verify_consistency_proof(tree, proof)
    if hash == old_root_hash do
      true
    else
      false
    end
  end

  defp do_verify_consistency_proof(tree, [first, second]) do
    Utils.make_hash(tree, first <> second)
  end

  defp do_verify_consistency_proof(tree, [head | tail]) do
    Utils.make_hash(tree, head <> do_verify_consistency_proof(tree, tail))
  end

  @spec insert(Types.tree, binary) :: Types.tree
  def insert(tree = %Bargad.Trees.Tree{size: 0}, x) do
    salted_node = tree.size + 1 |> Integer.to_string |> Utils.salt_node(x)
    node = Utils.make_node(tree, Utils.make_hash(tree, salted_node), [], 1, x)
    Utils.set_node(tree, node.hash, node)
    tree |> Map.put(:root, node.hash) |> Map.put(:size, 1)
  end

  @spec insert(Types.tree, binary) :: Types.tree
  def insert(tree = %Bargad.Trees.Tree{root: root,  size: size}, x) do
    root =
      tree
      |> Utils.get_node(root)
      |> get_new_root(tree, x)

    Utils.set_node(tree, root.hash, root)
    tree |> Map.put(:root, root.hash) |> Map.put(:size, size + 1)
  end

  defp get_new_root(root, tree, x) do
    l = root.size |> :math.log2() |> :math.ceil()

    if root.size == :math.pow(2, l) do
      salted_node = tree.size + 1 |> Integer.to_string() |> Utils.salt_node(x)
      right = Utils.make_node(tree, Utils.make_hash(tree, salted_node), [], 1, x)
      Utils.set_node(tree, right.hash, right)

      if tree.size > 1, do: Utils.delete_node(tree, root.hash)
      Utils.make_node(tree, root, right)
      else
        [left, right] = root.children
        left = Utils.get_node(tree, left)
        right = Utils.get_node(tree, right)
        boolean = left.size < :math.pow(2, l - 1)
        {left, right} = get_left_and_right_nodes(boolean, tree, root, left, right, x, l)

        Utils.delete_node(tree, root.hash)
        Utils.make_node(tree, left, right)
    end
  end

  defp get_left_and_right_nodes(true, tree, root, left, right, x, l) do
    left = do_insert(tree, root, left, x, l - 1, "L")
    {left, right}
  end

  defp get_left_and_right_nodes(false, tree, root, left, right, x, l) do
    right = do_insert(tree, root, right, x, l - 1, "R")
    {left, right}
  end

  defp do_insert(tree, parent, left = %Bargad.Nodes.Node{children: []}, _, _, "L")  do
    right = Utils.get_node(tree, List.last(parent.children))
    node = Utils.make_node(tree, left, right)
    Utils.set_node(tree, node.hash, node)
    node
  end

  defp do_insert(tree, _, left, x, _, "R")  do
    salted_node = tree.size + 1 |> Integer.to_string |> Utils.salt_node(x)
    right = Utils.make_node(tree, Utils.make_hash(tree, salted_node), [], 1, x)
    Utils.set_node(tree, right.hash, right)
    node = Utils.make_node(tree, left, right)
    Utils.set_node(tree, node.hash, node)
    node
  end
end
