#!/usr/bin/env python3
"""Select disjoint CI groups; unassigned tests always run in remaining."""
import sys

# Balanced using main's CI run 34439192628, when each group ran serially.
# Durations are serial test time, before setup. Each group now runs its
# classes in parallel on cloned Simulators.
GROUPS = {
    "accounts-and-discovery": [  # about 800 seconds serially
        "AccountUITests", "GroupUITests", "ProfileDefaultsUITests",
        "RSVPUITests", "DiscoveryPagingUITests", "DiscoveryVenueUITests", "DiscoveryArtworkUITests",
    ],
    # Includes the Swift Testing target and future test classes automatically.
    "remaining": None,  # about 800 seconds of UI tests serially
}


def selection(group):
    assigned = [name for classes in GROUPS.values() if classes for name in classes]
    if len(assigned) != len(set(assigned)):
        raise ValueError("A test class is assigned to more than one CI group")
    classes = GROUPS[group]
    prefix = "-skip-testing" if classes is None else "-only-testing"
    return [f"{prefix}:HuddlzUITests/{name}" for name in (assigned if classes is None else classes)]


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in GROUPS:
        sys.exit("Choose a CI group: " + ", ".join(GROUPS))
    print("\n".join(selection(sys.argv[1])))
