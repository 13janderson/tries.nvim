ok now i want to go one step further and think about the workflow for opening a try works.
- if we assume that every single try - script or project - has an entrypoint then running that try is as simple as running that entrypoint.
- whilst we could generalise this into just running the entry point executable directly, we should delegate the function of how to run a try to the languge implementation again.
- 
want a way to run a project. how could we cleanly implement this?
could go further and provide further configuration options for a particular language which we could expand into a separate picker with a keymap from the main one.
- things like asyncio python template, what else would be useful though?
- this is something you could just add incrementally as you found what you often repeated.
