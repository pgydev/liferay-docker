#!/bin/bash

function generate_release_properties_file {
	local bundle_file_name="liferay-dxp-tomcat-${_DXP_VERSION}-${_BUILD_TIMESTAMP}.7z"

	local product_version="DXP ${_DXP_VERSION^^}"

	product_version="${product_version/-/ }"

	local tomcat_version=$(grep -Eo "Apache Tomcat Version [0-9]+\.[0-9]+\.[0-9]+" "${_BUNDLES_DIR}/tomcat/RELEASE-NOTES")

	tomcat_version="${tomcat_version/Apache Tomcat Version /}"

	if [ -z "${tomcat_version}" ]
	then
		lc_log DEBUG "Cannot determine the Tomcat version."

		return 1
	fi

	(
		echo "app.server.tomcat.version=${tomcat_version}"
		echo "build.timestamp=${_BUILD_TIMESTAMP}"
		echo "bundle.checksum.sha512=$(cat "${bundle_file_name}.sha512")"
		echo "bundle.url=https://releases-cdn.liferay.com/dxp/${_DXP_VERSION}/${bundle_file_name}"
		echo "git.hash.liferay-docker=${_BUILDER_SHA}"
		echo "git.hash.liferay-portal-ee=${_GIT_SHA}"
		echo "liferay.docker.image=liferay/dxp:${_DXP_VERSION}"
		echo "liferay.docker.tags=${_DXP_VERSION}"
		echo "liferay.product.version=${product_version}"
		echo "release.date=$(date +"%Y-%m-%d")"
		echo "target.platform.version=${_DXP_VERSION}"
	) > release.properties
}

function generate_checksum_files {
	lc_cd "${_BUILD_DIR}"/release

	for file in *
	do
		if [ -f "${file}" ]
		then

			#
			# TODO Remove *.MD5 in favor of *.sha512.
			#

			md5sum "${file}" | sed -e "s/ .*//" > "${file}.MD5"

			sha512sum "${file}" | sed -e "s/ .*//" > "${file}.sha512"
		fi
	done
}

function install_patching_tool {
	trap 'return ${LIFERAY_COMMON_EXIT_CODE_BAD}' ERR

	lc_cd "${_BUNDLES_DIR}"

	if [ -e "patching-tool" ]
	then
		lc_log INFO "Patching Tool is already installed."

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	LIFERAY_COMMON_DOWNLOAD_SKIP_CACHE=true lc_download https://releases.liferay.com/tools/patching-tool/LATEST-4.0.txt

	local latest_version=$(cat LATEST-4.0.txt)

	rm -f LATEST-4.0.txt

	lc_log info "Installing Patching Tool ${latest_version}."

	lc_download https://releases.liferay.com/tools/patching-tool/patching-tool-"${latest_version}".zip

	unzip -q patching-tool-"${latest_version}".zip

	rm -f patching-tool-"${latest_version}".zip

	lc_cd patching-tool

	./patching-tool.sh auto-discovery

	rm -f logs/*
}

function package_boms {
	lc_cd "${_BUILD_DIR}/boms"

	cp -a ./*.pom "${_BUILD_DIR}/release"

	touch .touch

	jar cvfm "${_BUILD_DIR}/release/release.dxp.api-${_DXP_VERSION}-${_BUILD_TIMESTAMP}.jar" .touch -C api-jar .
	jar cvfm "${_BUILD_DIR}/release/release.dxp.api-${_DXP_VERSION}-${_BUILD_TIMESTAMP}-sources.jar" .touch -C api-sources-jar .

	rm -f .touch
}

function package_release {
	rm -fr "${_BUILD_DIR}/release"

	local package_dir="${_BUILD_DIR}/release/liferay-dxp"

	mkdir -p "${package_dir}"

	cp -a "${_BUNDLES_DIR}"/* "${package_dir}"

	echo "${_GIT_SHA}" > "${package_dir}"/.githash
	echo "${_DXP_VERSION}" > "${package_dir}"/.liferay-version

	touch "${package_dir}"/.liferay-home

	lc_cd "${_BUILD_DIR}/release"

	7z a "${_BUILD_DIR}/release/liferay-dxp-tomcat-${_DXP_VERSION}-${_BUILD_TIMESTAMP}.7z" liferay-dxp

	echo "liferay-dxp-tomcat-${_DXP_VERSION}-${_BUILD_TIMESTAMP}.7z" > "${_BUILD_DIR}"/release/.lfrrelease-tomcat-bundle

	tar czf "${_BUILD_DIR}/release/liferay-dxp-tomcat-${_DXP_VERSION}-${_BUILD_TIMESTAMP}.tar.gz" liferay-dxp

	zip -qr "${_BUILD_DIR}/release/liferay-dxp-tomcat-${_DXP_VERSION}-${_BUILD_TIMESTAMP}.zip" liferay-dxp

	lc_cd liferay-dxp

	zip -qr "${_BUILD_DIR}/release/liferay-dxp-osgi-${_DXP_VERSION}-${_BUILD_TIMESTAMP}.zip" osgi

	lc_cd tomcat/webapps/ROOT

	zip -qr "${_BUILD_DIR}/release/liferay-dxp-${_DXP_VERSION}-${_BUILD_TIMESTAMP}.war" ./*

	lc_cd "${_BUILD_DIR}/release/liferay-dxp"

	zip -qr "${_BUILD_DIR}/release/liferay-dxp-tools-${_DXP_VERSION}-${_BUILD_TIMESTAMP}.zip" tools

	lc_cd "${_PROJECTS_DIR}"/liferay-portal-ee

	cp -a sql liferay-dxp-sql

	zip -qr "${_BUILD_DIR}/release/liferay-dxp-sql-${_DXP_VERSION}-${_BUILD_TIMESTAMP}.zip" liferay-dxp-sql -i "*.sql"

	rm -fr liferay-dxp-sql

	rm -fr "${_BUILD_DIR}/release/liferay-dxp"
}