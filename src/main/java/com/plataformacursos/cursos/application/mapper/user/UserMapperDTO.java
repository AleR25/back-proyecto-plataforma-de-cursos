package com.plataformacursos.cursos.application.mapper.user;

import com.plataformacursos.cursos.application.dto.user.UserRequestDTO;
import com.plataformacursos.cursos.domain.model.users.UserModel;

import org.mapstruct.Mapper;

@Mapper(componentModel = "spring")
public interface UserMapperDTO {

    UserModel toModel(UserRequestDTO userRequestDTO);

    UserRequestDTO toDto(UserModel userModel);

}
