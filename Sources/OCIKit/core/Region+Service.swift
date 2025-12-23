//
//  Region+Service.swift
//
//
//  Created by Ilia Sazonov on 5/7/24.
//

import Foundation

public enum Region: String, CaseIterable {
  case syd, mel, gru, vcp, yul, yyz, scl, vap, bog, cdg, mrs, fra, hyd, bom,
    hsg, mtz, lin, kix, nrt, qro, mty, ams, ruh, jed, beg, sin, xsp, jnb,
    icn, yny, mad, arn, zrh, auh, dxb, lhr, cwl, iad, ord, phx, sjc

  var urlPart: String {
    switch self {
    case .syd: "ap-sydney-1"
    case .mel: "ap-melbourne-1"
    case .gru: "sa-saopaulo-1"
    case .vcp: "sa-vinhedo-1"
    case .yul: "ca-montreal-1"
    case .yyz: "ca-toronto-1"
    case .scl: "sa-santiago-1"
    case .vap: "sa-valparaiso-1"
    case .bog: "sa-bogota-1"
    case .cdg: "eu-paris-1"
    case .mrs: "eu-marseille-1"
    case .fra: "eu-frankfurt-1"
    case .hyd: "ap-hyderabad-1"
    case .bom: "ap-mumbai-1"
    case .hsg: "ap-batam-1"
    case .mtz: "il-jerusalem-1"
    case .lin: "eu-milan-1"
    case .kix: "ap-osaka-1"
    case .nrt: "ap-tokyo-1"
    case .qro: "mx-queretaro-1"
    case .mty: "mx-monterrey-1"
    case .ams: "eu-amsterdam-1"
    case .ruh: "me-riyadh-1"
    case .jed: "me-jeddah-1"
    case .beg: "eu-jovanovac-1"
    case .sin: "ap-singapore-1"
    case .xsp: "ap-singapore-2"
    case .jnb: "af-johannesburg-1"
    case .icn: "ap-seoul-1"
    case .yny: "ap-chuncheon-1"
    case .mad: "eu-madrid-1"
    case .arn: "eu-stockholm-1"
    case .zrh: "eu-zurich-1"
    case .auh: "me-abudhabi-1"
    case .dxb: "me-dubai-1"
    case .lhr: "uk-london-1"
    case .cwl: "uk-cardiff-1"
    case .iad: "us-ashburn-1"
    case .ord: "us-chicago-1"
    case .phx: "us-phoenix-1"
    case .sjc: "us-sanjose-1"
    }
  }

  public static func from(regionId: String) -> Region? {
    allCases.first { $0.urlPart == regionId }
  }
}

public enum Service: String {
  case language, objectstorage, generativeai, iam

  func getHost(in region: Region) -> String {
    switch self {
    case .language:
      "language.aiservice.\(region.urlPart).oci.oraclecloud.com"
    case .objectstorage:
      "objectstorage.\(region.urlPart).oraclecloud.com"
    case .generativeai:
      "inference.generativeai.\(region.urlPart).oci.oraclecloud.com"
    case .iam:
      "identity.\(region.urlPart).oci.oraclecloud.com"
    }
  }
}

/// Extracts the user's configured OCI region from an API key configuration file.
///
/// This helper reads the specified OCI config file (`~/.oci/config`)
/// and loads the profile's region value as interpreted by `SignerConfiguration`.
///
/// - Parameters:
///   - configPath:
///     The filesystem path to the OCI configuration file.
///   - profile:
///     The profile name within the config file to load.
///     Defaults to `"DEFAULT"`.
///
/// - Returns:
///   The region identifier (for example, `"eu-frankfurt-1"`) if present in the
///   configuration file, or `nil` if the profile does not define a region.
public func extractUserRegion(from configPath: String, profile: String = "DEFAULT") throws -> String? {
  let signerConfig = try SignerConfiguration.fromFileForAPIKey(
    configFilePath: configPath,
    configName: profile
  )
  return signerConfig.region
}

/// Extracts the tenancy OCID from an API key configuration file.
///
/// This helper loads the specified OCI config file and returns the tenancy OCID
/// associated with the given profile. The tenancy OCID uniquely identifies the
/// root compartment of the tenancy.
///
/// - Parameters:
///   - configPath:
///     The filesystem path to the OCI configuration file.
///   - profile:
///     The profile name within the config file to load.
///     Defaults to `"DEFAULT"`.
///
/// - Returns:
///   The tenancy OCID if present in the configuration file, or `nil` if the
///   profile does not define one.
public func extractTenancyId(from configPath: String, profile: String = "DEFAULT") throws -> String? {
  let signerConfig = try SignerConfiguration.fromFileForAPIKey(
    configFilePath: configPath,
    configName: profile
  )
  return signerConfig.tenancyOCID
}
