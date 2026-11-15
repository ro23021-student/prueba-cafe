//! Backend en Rust con Clean Architecture. Las dependencias apuntan hacia adentro:
//!   interface -> application -> domain      infrastructure -> application (implementa puertos)
//! `domain` no conoce HTTP, JSON de CouchDB ni ningun framework.
pub mod application;
pub mod config;
pub mod domain;
pub mod infrastructure;
pub mod interface;
