# Dendritic Pattern Principles

## Core Concepts and Philosophy

The dendritic pattern is a revolutionary approach to Nix configuration organization that fundamentally transforms how modules interact and grow within your system. Like dendrites in biological neural networks that automatically form connections, your Nix modules automatically discover and wire themselves together without explicit imports.

## What Is the Dendritic Pattern?

The dendritic pattern is an architectural approach where:

1. **Every `.nix` file is a flake-parts module** - No special module types, no complex hierarchies
2. **Modules are automatically imported** - Using `import-tree`, eliminating manual import management
3. **Files organize themselves by concern** - Directory structure reflects functionality, not import requirements
4. **Modules extend and compose naturally** - Like dendrites growing and connecting in a neural network

### The Biological Metaphor

Just as dendrites in neurons:

- Automatically find and connect to other neurons
- Form complex networks without central planning
- Can reorganize and adapt as the system evolves
- Create emergent behavior from simple rules

Your Nix configuration:

- Automatically discovers and loads all modules
- Forms complex systems from simple, focused modules
- Can be reorganized freely without breaking connections
- Creates sophisticated configurations from composable parts

## Why the Dendritic Pattern Exists

### The Problem with Traditional Nix Configurations

Traditional Nix configurations suffer from:

1. **Import Hell** - Complex webs of relative imports that break when files move
2. **Rigid Structure** - File organization dictated by import dependencies
3. **Refactoring Fear** - Moving files requires updating multiple import statements
4. **Poor Discoverability** - Understanding module relationships requires tracing imports
5. **Composition Complexity** - Mixing and matching modules requires manual wiring

### The Dendritic Solution

The pattern solves these problems through:

1. **Zero Import Maintenance** - Files never reference each other by path
2. **Organic Organization** - Files live where they make semantic sense
3. **Refactoring Freedom** - Move files without updating any imports
4. **Self-Documenting Structure** - Directory structure reveals system architecture
5. **Natural Composition** - Modules compose through flake-parts' powerful module system

## Benefits Over Traditional Configurations

### 1. Maintenance Simplicity

**Traditional:**

```nix
# configuration.nix
{ ... }: {
  imports = [
    ./hardware-configuration.nix
    ./users/alice.nix
    ../modules/desktop.nix
    ../../common/base.nix  # Break if any directory moves
  ];
}
```

**Dendritic:**

```nix
# All modules automatically imported - no maintenance needed
# modules/mysystem/imports.nix
{ config, ... }: {
  configurations.nixos.mysystem.module = {
    imports = with config.flake.modules.nixos; [
      base
      desktop
      # Reference by name, not path
    ];
  };
}
```

### 2. Evolutionary Growth

Your configuration grows organically:

- Start with a few modules
- Add new capabilities by dropping in files
- Reorganize as patterns emerge
- Split modules when they grow too large
- No architectural decisions required upfront

### 3. Type Safety and Validation

Flake-parts provides:

- Strong typing for all module options
- Compile-time validation
- Clear error messages
- IDE support through nil/nixd

### 4. Composability

Modules compose at multiple levels:

```
base → pc → workstation → your-specific-system
     ↘ server → web-server → your-server
```

## The Automatic Import Mechanism

### How Import-Tree Works

The magic happens through one line in your flake:

```nix
imports = [ (inputs.import-tree ./modules) ];
```

This:

1. Recursively scans the `./modules` directory
2. Loads every `.nix` file as a flake-parts module
3. Ignores files/directories prefixed with `_`
4. Merges all modules into your flake configuration

### File Discovery Rules

- **Included:** All files ending in `.nix`
- **Excluded:** Files/directories starting with `_`
- **Recursive:** Processes all subdirectories
- **Order-Independent:** Load order doesn't matter due to lazy evaluation

### Module Evaluation

Each file becomes a function:

```nix
{ lib, config, inputs, ... }: {
  # Your module content
}
```

These are standard flake-parts modules with access to:

- `lib` - Nixpkgs library functions
- `config` - The complete flake configuration
- `inputs` - All flake inputs
- Plus standard module system arguments

## The "Named Modules As Needed" Philosophy

### The Core Principle

**Only create a named module when configuration is needed by SOME but not ALL systems.**

This principle prevents unnecessary abstraction and keeps your configuration lean and purposeful.

### Decision Tree for Module Creation

```
Is this configuration needed by all systems?
├─ YES → Extend an existing module (like base)
└─ NO → Is it needed by multiple systems?
    ├─ YES → Create a named module
    └─ NO → Put it in the specific system's configuration
```

### Examples of Good Named Modules

✅ **`flake.modules.nixos.laptop`**

- Needed by: Laptop systems
- Not needed by: Desktops, servers
- Contains: Battery management, Wi-Fi, touchpad

✅ **`flake.modules.nixos.development`**

- Needed by: Development machines
- Not needed by: Production servers, kiosks
- Contains: Compilers, editors, debugging tools

✅ **`flake.modules.nixos.nvidia-gpu`**

- Needed by: Systems with NVIDIA GPUs
- Not needed by: Systems with AMD/Intel graphics
- Contains: NVIDIA drivers, CUDA support

### Examples of Bad Named Modules

❌ **`flake.modules.nixos.nix-settings`**

- Why bad: Every NixOS system needs Nix
- Better: Extend `base` module directly

❌ **`flake.modules.nixos.single-package`**

- Why bad: Too granular, creates module proliferation
- Better: Group related packages in semantic modules

❌ **`flake.modules.nixos.my-specific-server`**

- Why bad: Only used by one system
- Better: Put directly in that system's configuration

## When to Create vs Extend Modules

### Create a New Named Module When:

1. **Multiple systems share configuration**

   - But not all systems need it
   - Clear semantic grouping exists
   - Likelihood of reuse is high

2. **Hardware variations require different settings**

   - GPU vendors (NVIDIA vs AMD)
   - System types (laptop vs desktop)
   - Architectures (x86_64 vs aarch64)

3. **Roles are clearly defined**
   - Development vs production
   - Workstation vs server
   - Personal vs shared

### Extend Existing Modules When:

1. **All systems need the configuration**

   ```nix
   # modules/git/enable.nix
   {
     flake.modules.homeManager.base.programs.git.enable = true;
   }
   ```

2. **Adding to semantic groups**

   ```nix
   # modules/shells/bash.nix
   {
     flake.modules.homeManager.base.programs.bash = {
       enable = true;
       enableCompletion = true;
     };
   }
   ```

3. **Configuration is foundational**
   ```nix
   # modules/nix/settings.nix
   {
     flake.modules.nixos.base.nix.settings = {
       experimental-features = [ "nix-command" "flakes" "pipe-operators" ];
       trusted-users = [ "root" "@wheel" ];
     };
   }
   ```

## Anti-Patterns to Avoid

### 1. Path-Based Imports

❌ **Never do this:**

```nix
{
  imports = [ ./some-module.nix ];
}
```

✅ **Always use named references:**

```nix
{
  imports = with config.flake.modules.nixos; [ base pc ];
}
```

### 2. Over-Modularization

❌ **Too granular:**

```nix
# One module per package
modules/packages/wget.nix
modules/packages/git.nix
modules/packages/vim.nix
```

✅ **Semantic grouping:**

```nix
# Group by purpose
modules/cli-tools.nix  # wget, curl, git, vim, etc.
```

### 3. Module Inheritance Chains

❌ **Deep inheritance:**

```nix
base → base-plus → base-plus-plus → base-ultimate → actual-system
```

✅ **Flat composition:**

```nix
base → pc → workstation
base → server → web-server
```

### 4. Circular Dependencies

❌ **Modules depending on each other:**

```nix
# moduleA extends moduleB
# moduleB extends moduleA
```

✅ **One-way dependencies:**

```nix
# Clear hierarchy: base ← pc ← workstation
```

### 5. Special Args Pass-Through

❌ **Leaking implementation details:**

```nix
specialArgs = { inherit inputs; };
```

✅ **Module receives what it needs:**

```nix
{ config, inputs, ... }: {
  # inputs available automatically via flake-parts
}
```

## Module Organization Principles

### 1. Semantic Grouping

Organize by functionality, not technical implementation:

```
modules/
├── audio/          # All audio-related configuration
├── networking/     # Network configuration
├── shells/         # Shell configurations
└── security/       # Security settings
```

### 2. System-Specific Directories

Keep system-specific configuration isolated:

```
modules/
├── laptop1/        # Everything specific to laptop1
├── server1/        # Everything specific to server1
└── shared/         # Shared configurations
```

### 3. Progressive Enhancement

Build from general to specific:

```
base (foundation for all)
  ├── pc (adds GUI capabilities)
  │   ├── workstation (adds development tools)
  │   └── gaming (adds gaming support)
  └── server (headless operation)
      ├── web-server (adds web serving)
      └── build-server (adds CI/CD capabilities)
```

### 4. Cross-Cutting Concerns

Handle aspects that affect multiple modules:

```
modules/
├── style/          # Theming, fonts, colors
├── security/       # Security policies
├── monitoring/     # System monitoring
└── backup/         # Backup strategies
```

## The Power of Composition

### Module Composition Patterns

1. **Additive Composition**

   ```nix
   # Each module adds capabilities
   imports = [ base networking audio graphics ];
   ```

2. **Override Composition**

   ```nix
   # Later modules can override earlier ones
   imports = [ defaults customizations ];
   ```

3. **Conditional Composition**
   ```nix
   # Include modules based on conditions
   imports = [ base ]
     ++ lib.optional hasGpu gpu-support
     ++ lib.optional isLaptop power-management;
   ```

### Composition Benefits

- **Flexibility:** Mix and match modules for different systems
- **Reusability:** Share modules across multiple configurations
- **Testability:** Test modules in isolation
- **Maintainability:** Changes in one module don't affect others

## Critical Requirements

### Pipe Operators Are Mandatory

The dendritic pattern heavily uses pipe operators for clarity:

```nix
# Always enable in nixConfig
nixConfig.extra-experimental-features = [ "pipe-operators" ];

# Always use in commands
nix build .#something --extra-experimental-features pipe-operators
```

### Zero-Warning Policy

```nix
nixConfig.abort-on-warn = true;
```

This ensures:

- Clean evaluations
- No deprecated features
- Consistent code quality
- Early error detection

## Pattern Evolution

The dendritic pattern encourages evolutionary development:

1. **Start Simple** - Begin with basic modules
2. **Grow Organically** - Add modules as needs arise
3. **Refactor Naturally** - Reorganize when patterns emerge
4. **Split Thoughtfully** - Divide modules when they become too large
5. **Compose Creatively** - Combine modules in new ways

## Summary

The dendritic pattern represents a paradigm shift in Nix configuration:

- **From manual wiring to automatic discovery**
- **From rigid structure to organic organization**
- **From import management to semantic focus**
- **From monolithic configurations to composable modules**
- **From refactoring fear to reorganization freedom**

By embracing these principles, your Nix configuration becomes a living, growing system that adapts to your needs while remaining maintainable and understandable.
