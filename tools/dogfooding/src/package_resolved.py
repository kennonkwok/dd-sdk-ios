# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-2020 Datadog, Inc.
# -----------------------------------------------------------

import json
from copy import deepcopy


class PackageResolvedFile:
    """
    Abstracts operations on `Package.resolved` file.
    """

    __SUPPORTED_PACKAGE_RESOLVED_VERSION = 1

    def __init__(self, path: str):
        print(f'⚙️ Opening {path}')
        self.path = path
        with open(path, 'r') as file:
            self.packages = json.load(file)
            version = self.packages['version']
            if version != self.__SUPPORTED_PACKAGE_RESOLVED_VERSION:
                raise Exception(
                    f'{path} uses version {version} but `package_resolved.py` supports ' +
                    f'version {self.__SUPPORTED_PACKAGE_RESOLVED_VERSION}. Update `package_resolved.py` to new format.'
                )

    def update_dependency(self, package_name: str, new_branch, new_revision, new_version):
        """
        Updates dependency resolution values.
        :param package_name: the name of the package to update
        :param new_branch: the new branch name (pass `None` for `null`)
        :param new_revision: the new revision (pass `None` for `null`)
        :param new_version: the new version name (pass `None` for `null`)
        :return:
        """
        package = self.__get_package(package_name=package_name)

        # Individual package pin looks this:
        # {
        #     "package": "DatadogSDK",
        #     "repositoryURL": "https://github.com/DataDog/dd-sdk-ios",
        #     "state": {
        #         "branch": "dogfooding",
        #         "revision": "4e93a8f1f662d9126074a0f355b4b6d20f9f30a7",
        #         "version": null
        #     }
        # }

        old_state = deepcopy(package['state'])

        package['state']['branch'] = new_branch
        package['state']['revision'] = new_revision
        package['state']['version'] = new_version

        new_state = deepcopy(package['state'])

        diff = old_state.items() ^ new_state.items()

        if len(diff) > 0:
            print(f'✏️️ Updated "{package_name}":')
            print(f'    → old: {old_state}')
            print(f'    → new: {new_state}')
        else:
            print(f'✏️️ "{package_name}" is up-to-date')

    def read_dependency(self, package_name):
        """
        Returns resolution info for given dependency.
        :param package_name: the name of dependency
        :return: `state` object from `Package.resolved`
        """
        package = self.__get_package(package_name=package_name)
        return deepcopy(package['state'])

    def get_number_of_dependencies(self):
        """
        :return: number of dependencies
        """
        return len(self.packages['object']['pins'])

    def save(self):
        """
        Saves changes to initial `path`.
        """
        print(f'⚙️ Saving {self.path}')
        with open(self.path, 'w') as file:
            json.dump(
                self.packages,
                fp=file,
                indent=2,  # preserve `swift package` indentation
                sort_keys=True  # preserve `swift package` packages sorting
            )
            file.write('\n')  # add new line to the EOF

    def __get_package(self, package_name: str):
        pins = self.packages['object']['pins']
        package_pins = [index for index, p in enumerate(pins) if p['package'] == package_name]

        if len(package_pins) == 0:
            raise Exception(
                f'{self.path} does not contain pin named "{package_name}"'
            )

        package_pin_index = package_pins[0]
        return self.packages['object']['pins'][package_pin_index]
