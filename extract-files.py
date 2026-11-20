#!/usr/bin/env -S PYTHONPATH=../../../tools/extract-utils python3
#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

from extract_utils.fixups_blob import (
    blob_fixup,
    blob_fixups_user_type,
)
from extract_utils.main import (
    ExtractUtils,
    ExtractUtilsModule,
)

blob_fixups: blob_fixups_user_type = {
    # The shim has to come first, ahead of libaudioclient: it also defines
    # AudioTrack methods. See shims/vtservice.cpp.
    'system/bin/vtservice': blob_fixup()
        .add_needed('libshim_vtservice.so'),
}  # fmt: skip

module = ExtractUtilsModule(
    's88pro',
    'doogee',
    blob_fixups=blob_fixups,
)

if __name__ == '__main__':
    utils = ExtractUtils.device(module)
    utils.run()
