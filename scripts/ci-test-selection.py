#!/usr/bin/env python3
"""Select disjoint CI groups; unassigned tests always run in remaining."""
import sys

# Balanced using main's CI run 34439192628. Durations are test time, before setup.
GROUPS = {
    "accounts": [  # 404 seconds
        "AccountUITests", "GroupUITests", "ProfileDefaultsUITests",
    ],
    "rsvp-and-discovery": [  # 392 seconds
        "RSVPUITests", "DiscoveryPagingUITests", "DiscoveryVenueUITests", "DiscoveryArtworkUITests",
    ],
    "location-and-joining": [  # 404 seconds
        "DiscoveryLocationUITests", "JoiningUITests", "SignupCityUITests",
        "SearchBadgeUITests", "HuddlzUITestsLaunchTests",
    ],
    # Includes the Swift integration target and future test classes automatically.
    "remaining": None,  # 401 seconds of UI tests
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
