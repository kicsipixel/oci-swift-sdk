//
//  X509FederationClientBasedSecurityTokenSigner.swift
//  oci-swift-sdk
//
//  Created by Ilia Sazonov on 9/14/25.
//

import Foundation

public final class X509FederationClientBasedSecurityTokenSigner: Signer {
    private let federationClient: X509FederationClientProtocol
    
    public init(federationClient: X509FederationClientProtocol) {
        self.federationClient = federationClient
    }
    
    public func sign(_ req: inout URLRequest) throws {
        let token = try federationClient.currentSecurityToken()
        let key = try federationClient.currentPrivateKey()
        var delegateSigner = SecurityTokenSigner(securityToken: token, privateKey: key)
        try delegateSigner.sign(&req)
    }
}
