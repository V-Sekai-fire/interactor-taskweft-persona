# In C node mode the VM has to be distributed and the node has to be running.
if function_exported?(Persona.Native, :start_link, 1) do
  {:ok, _} = Node.start(:persona_test, :shortnames)
  {:ok, _} = Persona.Native.start_link()
end

ExUnit.start()
